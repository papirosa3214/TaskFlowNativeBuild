import SwiftUI

/// Вкладка «План» экрана «Координация»: что сделано, что ждём, полотно этапов.
/// Здесь же меняется сам план: этапы добавляются, распараллеливаются и
/// убираются прямо на ходу. Переписка по задаче — во вкладке «Лента».
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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                banners
                // Только граф (владелец 12.11.2026: «в плане оставил бы
                // исключительно сам граф»). Сводка, «Сделано», «В работе и
                // дальше» и контекст есть в «Ходе» и «Миссии»; изменения кода
                // отсюда тоже сняты.
                if let plan = board.plan {
                    boardSection(plan)
                } else if refreshing || !loadedOnce {
                    TFLoading(.inline).frame(maxWidth: .infinity)
                } else {
                    TFEmptyState(icon: "point.3.connected.trianglepath.dotted", text: "Нет утверждённого плана",
                                 description: "Этапы появятся здесь после утверждения плана.")
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
        .tfSheet(item: $sheet) { boardSheet($0) }
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

    private func boardSection(_ plan: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TFPlainSectionTitle("Этапы")
                .padding(.horizontal, TFSpacing.screenHorizontal)
            CoordinationBoardView(plan: plan, model: board, editable: canEdit,
                                  onSelect: { sheet = .stage($0) }, onAdd: { sheet = .add($0) })
        }
        .hintAnchor(HintAnchorID.taskCoordination)
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
        do {
            let items = try await APIClient().fetchTaskResolutions(taskId: taskId)
            guard !Task.isCancelled else { return }
            state.apply(resolutions: items, contractVersion: items.first?.contractVersion)
            state.pruneStaleNodes(olderThan: Date().addingTimeInterval(-300))
        } catch {
            if !Task.isCancelled { state.applyFailure(error.localizedDescription) }
        }
    }
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
