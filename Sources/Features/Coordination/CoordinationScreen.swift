import SwiftUI

/// Собственная жизнь панели: закрытие sheet отменяет обновление данных.
struct TaskCoordinationScreen: View {
    let taskID: String
    var allowsPlanChanges = true
    let onOpenTaskControls: () -> Void
    @StateObject private var state = CoordinationState()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CoordinationScreen(state: state, taskId: taskID, allowsPlanChanges: allowsPlanChanges,
                               onOpenTaskControls: onOpenTaskControls)
                .navigationTitle("Координация")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    routeDestination(route)
                }
        }
    }
}

/// Рабочее место владельца по командному плану: что сделано, что ждём, полотно
/// этапов и переписка. Здесь же меняется сам план: этапы добавляются,
/// распараллеливаются и убираются прямо на ходу.
public struct CoordinationScreen: View {
    @ObservedObject public var state: CoordinationState
    public let taskId: String
    public let refreshIntervalSeconds: Double
    public let allowsPlanChanges: Bool
    public let onOpenTaskControls: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SessionStore.self) private var session
    @State private var board = CoordinationBoardModel()
    @State private var refreshing = false
    @State private var loadedOnce = false
    @State private var sheet: BoardSheet?
    @State private var executorSummary: TaskExecutorSummary?
    /// Переписка по задаче — тема, где видно ответы исполнителей.
    @State private var taskChatID: String?

    private enum BoardSheet: Identifiable {
        case stage(String)
        case add(CoordinationBoard.StepPreset)
        var id: String {
            switch self {
            case .stage(let slot): "stage-\(slot)"
            case .add(let preset): "add-\(preset.after)-\(preset.before)"
            }
        }
    }

    public init(state: CoordinationState, taskId: String, refreshIntervalSeconds: Double = 30,
                allowsPlanChanges: Bool = true, onOpenTaskControls: @escaping () -> Void) {
        self.state = state
        self.taskId = taskId
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.allowsPlanChanges = allowsPlanChanges
        self.onOpenTaskControls = onOpenTaskControls
    }

    private var isOwner: Bool { session.currentUser?.role == .owner }
    private var compatible: Bool {
        if case .versionMismatch = state.loadState { return false }
        return true
    }
    private var canEdit: Bool { isOwner && allowsPlanChanges && board.ownsStructure && compatible }
    private var stages: [CoordinationStage] { board.orderedStages }
    private var done: [CoordinationStage] { stages.filter(\.isDone) }
    private var ahead: [CoordinationStage] { stages.filter { !$0.isDone && !$0.isSkipped } }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                banners
                if let plan = board.plan {
                    summary
                    boardSection(plan)
                    if !done.isEmpty { stageList("Сделано", stages: done) { $0.result ?? $0.node.expectedResult } }
                    if !ahead.isEmpty { stageList("В работе и дальше", stages: ahead) { $0.node.expectedResult } }
                } else if refreshing || !loadedOnce {
                    TFLoading(.inline).frame(maxWidth: .infinity)
                } else {
                    TFEmptyState(icon: "point.3.connected.trianglepath.dotted", text: "Нет утверждённого плана",
                                 description: "Этапы появятся здесь после утверждения плана.")
                }
                codeChangesSection
                if isOwner, let context = board.context {
                    TaskContextSection(context: context)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                }
                chatRow
                if let updated = state.lastUpdatedAt {
                    Text("Обновлено \(updated.formatted(date: .omitted, time: .shortened))")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                }
            }
            .padding(.vertical, TFSpacing.md)
        }
        .tfScreenBackground()
        .refreshable { await refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(max(1, refreshIntervalSeconds))) }
                catch { return }
            }
        }
        .sheet(item: $sheet) { boardSheet($0) }
        .sheet(isPresented: Binding(
            get: { taskChatID != nil },
            set: { if !$0 { taskChatID = nil } }
        )) {
            if let taskChatID { TaskChatSheet(chatID: taskChatID) }
        }
        .alert("План не изменён", isPresented: Binding(
            get: { board.errorMessage != nil },
            set: { if !$0 { board.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { board.errorMessage = nil }
        } message: {
            Text(board.errorMessage ?? "")
        }
    }

    // MARK: - Разделы

    @ViewBuilder
    private var banners: some View {
        if case .failed(let error) = state.loadState {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFErrorBanner("Не удалось обновить статус. Показаны последние полученные данные. \(error)", variant: .block)
                TFActionRow(title: "Повторить", icon: "arrow.clockwise", isEnabled: !refreshing) {
                    Task { await refresh() }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
        if !compatible {
            Text("Версия данных сервера изменилась. Просмотр доступен, действия отключены.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    /// Сводка одним взглядом: сколько сделано и кому что нужно.
    private var summary: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            let total = stages.filter { !$0.isSkipped }.count
            Text("Сделано \(done.count) из \(total)")
                .tfText(.title)
                .foregroundStyle(Color.tfText)
            Text(summaryLine)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private var summaryLine: String {
        var parts: [String] = []
        let active = stages.filter(\.isActive).count
        let needsOwner = stages.filter(\.needsOwner).count
        let questions = executorSummary?.pendingQuestions.count ?? 0
        if active > 0 { parts.append("в работе \(active)") }
        if needsOwner > 0 { parts.append("ждут вас \(needsOwner)") }
        if questions > 0 { parts.append("вопросов к вам \(questions)") }
        let waiting = ahead.count - active - needsOwner
        if waiting > 0 { parts.append("впереди \(waiting)") }
        return parts.isEmpty ? "Все этапы закрыты" : parts.joined(separator: " · ").capitalizedFirst
    }

    private func boardSection(_ plan: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TFPlainSectionTitle("Этапы")
                .padding(.horizontal, TFSpacing.screenHorizontal)
            CoordinationBoardView(plan: plan, model: board, editable: canEdit,
                                  onSelect: { sheet = .stage($0) }, onAdd: { sheet = .add($0) })
        }
        .hintAnchor(HintAnchorID.taskCoordination)
    }

    /// Сжатый список: роль и пара строк, полный текст в панели этапа.
    private func stageList(_ title: String, stages: [CoordinationStage],
                           text: @escaping (CoordinationStage) -> String) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TFPlainSectionTitle(title)
            ForEach(stages) { stage in
                Button { sheet = .stage(stage.id) } label: {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                            Text(board.roleTitle(stage.node.roleKey))
                                .tfText(.body)
                                .foregroundStyle(Color.tfText)
                            Spacer(minLength: 0)
                            Text(stage.label)
                                .tfText(.caption)
                                .foregroundStyle(stage.tint)
                        }
                        Text(text(stage))
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TFTapRowStyle())
                .accessibilityIdentifier("coord.row.\(stage.id)")
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Что реально изменилось в коде: раскрывается здесь же, до диффа по файлу.
    @ViewBuilder
    private var codeChangesSection: some View {
        if isOwner, !board.codeChanges.isEmpty {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                TFPlainSectionTitle("Изменения кода")
                ForEach(board.codeChanges, id: \.taskID) { changes in
                    TaskCodeChangesDisclosure(
                        changes: changes,
                        title: board.codeChanges.count > 1 ? board.cardTitle(changes.taskID) : nil
                    )
                }
                Text("Показана вся ветка карточки: роли работают в одной ветке, поэтому по этапам изменения не разделяются.")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    private var chatRow: some View {
        TFActionRow(title: "Переписка по задаче", icon: "bubble.left.and.bubble.right") {
            Task {
                if let chat = try? await APIClient().taskTopic(taskID: taskId) {
                    taskChatID = chat.id
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .accessibilityIdentifier("coordination.task-chat")
    }

    // MARK: - Шторки

    @ViewBuilder
    private func boardSheet(_ sheet: BoardSheet) -> some View {
        switch sheet {
        case .stage(let slot):
            CoordinationStageSheet(
                taskID: taskId, slot: slot, model: board, editable: canEdit,
                resolution: board.stage(slot)?.subtask.flatMap { state.resolution(forSubtaskId: $0.id) },
                compatible: compatible,
                onOpenTaskControls: onOpenTaskControls,
                onChanged: { Task { await refresh() } }
            )
        case .add(let preset):
            if let plan = board.plan {
                PlanStepEditorSheet(
                    mode: .add, plan: plan, roles: board.roleOptions, pendingSlots: board.pendingSlots,
                    roleTitle: board.roleTitle(_:),
                    onSave: { op in
                        Task {
                            await board.apply([op], taskID: taskId, isOwner: isOwner)
                            await refresh()
                        }
                    },
                    preset: preset
                )
            }
        }
    }

    // MARK: - Данные

    @MainActor private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer {
            refreshing = false
            loadedOnce = true
        }
        await board.load(taskID: taskId, isOwner: isOwner)
        if isOwner {
            await board.loadCodeChanges(taskID: taskId)
            await board.loadContext(taskID: taskId)
        }
        do {
            let items = try await APIClient().fetchTaskResolutions(taskId: taskId)
            guard !Task.isCancelled else { return }
            state.apply(resolutions: items, contractVersion: items.first?.contractVersion)
            state.pruneStaleNodes(olderThan: Date().addingTimeInterval(-300))
        } catch {
            if !Task.isCancelled { state.applyFailure(error.localizedDescription) }
        }
        // Сводка отдельным запросом и без фатальности: без неё экран работает,
        // пропадает только счётчик вопросов к владельцу.
        if let summary = try? await APIClient().taskExecutorSummary(taskId: taskId) {
            executorSummary = summary
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

public struct ResolutionDetailsSheet: View {
    public let resolution: APIClient.CoordinationResolution?
    @Environment(\.dismiss) private var dismiss
    public init(resolution: APIClient.CoordinationResolution?) { self.resolution = resolution }
    public var body: some View {
        NavigationStack {
            List {
                if let r = resolution {
                    TFPlainSection(r.displayTitle) {
                        Text(r.displayStatus).tfText(.body).foregroundStyle(Color.tfText)
                        if let notes = r.notes {
                            Text(notes).tfText(.body).foregroundStyle(Color.tfText).textSelection(.enabled)
                        }
                    }
                    if !r.evidence.isEmpty {
                        TFPlainSection("Основания") {
                            ForEach(Array(r.evidence.enumerated()), id: \.offset) { _, item in
                                Text(item.ref).tfText(.action).foregroundStyle(Color.tfSub).textSelection(.enabled)
                            }
                        }
                    }
                    TFPlainSection("Данные") {
                        TFInfoRow(label: "Версия", value: r.contractVersion)
                        TFInfoRow(label: "Обновлено сервером", value: r.generatedAt)
                    }
                } else {
                    Text("Нет данных").tfText(.body).foregroundStyle(Color.tfSub)
                }
            }
            .listStyle(.plain)
            .tfScreenBackground()
            .navigationTitle("Состояние шага")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
