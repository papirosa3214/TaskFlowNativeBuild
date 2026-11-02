import SwiftUI

/// Собственная жизнь панели: закрытие sheet отменяет обновление данных.
struct TaskCoordinationScreen: View {
    let taskID: String
    let onOpenTaskControls: () -> Void
    @StateObject private var state = CoordinationState()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CoordinationScreen(state: state, taskId: taskID, onOpenTaskControls: onOpenTaskControls)
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

/// Причины, зависимости и управление выбранным шагом. Без демонстрационных сообщений.
public struct CoordinationScreen: View {
    @ObservedObject public var state: CoordinationState
    public let taskId: String
    public let refreshIntervalSeconds: Double
    public let onOpenTaskControls: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var refreshing = false
    @State private var performingAction = false
    @State private var showRestart = false
    @State private var restartTarget: APIClient.CoordinationResolution?
    @State private var reason = ""
    @State private var actionError: String?
    @State private var showDetails = false
    /// Слот, для которого открыто окно исполнителя (тап по узлу графа).
    @State private var executorSlotID: String?
    /// Сводка по исполнителям — нужна для кнопки «Написать оркестратору».
    @State private var executorSummary: TaskExecutorSummary?
    /// Переписка по задаче — тема, где видно ответы исполнителей.
    @State private var taskChatID: String?

    public init(state: CoordinationState, taskId: String, refreshIntervalSeconds: Double = 30,
                onOpenTaskControls: @escaping () -> Void) {
        self.state = state
        self.taskId = taskId
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.onOpenTaskControls = onOpenTaskControls
    }

    private var selected: APIClient.CoordinationResolution? {
        if let selectedID { return state.resolution(forSubtaskId: selectedID) }
        if let stalled = state.stalledNodeId { return state.resolution(forSubtaskId: stalled) }
        return state.nodes.compactMap(\.resolution).first
    }
    private var compatible: Bool {
        if case .versionMismatch = state.loadState { return false }
        return true
    }
    private var canAct: Bool {
        state.loadState == .loaded && !refreshing && !performingAction
    }

    public var body: some View {
        List {
            if case .failed(let error) = state.loadState {
                Section {
                    Text("Не удалось обновить статус. Показаны последние полученные данные.")
                    Text(error).tfText(.meta)
                    Button("Повторить") { Task { await refresh() } }.disabled(refreshing)
                }
            }
            if !compatible {
                Text("Версия данных сервера изменилась. Просмотр доступен, действия отключены.")
            }
            if state.nodes.isEmpty {
                Section {
                    if refreshing { TFLoading(.inline) }
                    else { Text("Нет данных о выполнении задачи") }
                }
            } else {
                Section("Состояние шагов") {
                    ResolutionGraph(state: state) { nodeID in
                        // Тап по узлу графа открывает окно исполнителя:
                        // кто делает шаг, чего ждёт и что ему сказать
                        // (владелец 02.11.2026).
                        selectedID = nodeID
                        executorSlotID = nodeID
                    }
                }
                Section("Шаги") {
                    ForEach(state.nodes) { node in
                        Button {
                            selectedID = node.id
                            actionError = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                    Text(node.resolution?.displayTitle ?? "Шаг временно недоступен").tfText(.body)
                                    Text(node.resolution?.displayStatus ?? "Обновите данные").tfText(.meta)
                                }
                                Spacer()
                                if node.id == selected?.id { Image(systemName: "checkmark") }
                            }
                        }
                        .accessibilityLabel(node.resolution?.displayTitle ?? "Шаг недоступен")
                        .accessibilityValue(node.resolution?.displayStatus ?? "Нет данных")
                    }
                }
                .hintAnchor(HintAnchorID.taskCoordination)
            }
            // Управление процессом из одного окна: написать оркестратору,
            // который решает, кто что делает, или открыть переписку по задаче,
            // где видно ответы исполнителей (владелец 02.11.2026).
            Section("Управление") {
                if let orchestratorSlot = executorSummary?.orchestrator.slotId {
                    Button {
                        executorSlotID = orchestratorSlot
                    } label: {
                        Label("Написать оркестратору", systemImage: "crown")
                    }
                    .accessibilityIdentifier("coordination.orchestrator")
                    Text("Оркестратор разложил работу по ролям — ему можно написать прямо отсюда.")
                        .tfText(.meta)
                }
                Button {
                    Task {
                        if let chat = try? await APIClient().taskTopic(taskID: taskId) {
                            taskChatID = chat.id
                        }
                    }
                } label: {
                    Label("Переписка по задаче", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier("coordination.task-chat")
            }
            // Контракт миссии — те же критерии, что проверяет этот экран, но
            // записанные ДО работы: список ассерций, что не пройдено и журнал
            // прохождения. Отдельный маршрут, потому что это пуш, а не
            // действие над шагом.
            Section("Контракт миссии") {
                NavigationLink(value: AppRoute.missionControl(taskID: taskId)) {
                    Text("Mission Control").tfText(.body)
                }
                .hintAnchor(HintAnchorID.missionControl)
                .accessibilityIdentifier("coordination.mission-control")
                Text("Что считается готовым по критериям, записанным до работы.")
                    .tfText(.meta)
            }
            if let r = selected {
                Section(r.displayTitle) {
                    Text(r.displayStatus).tfText(.body)
                    LabeledContent("Ответственный", value: r.assigneeName ?? "Не указан сервером")
                    if let notes = r.notes, !notes.isEmpty {
                        Text(notes).tfText(.body).textSelection(.enabled)
                    }
                    if let waiting = r.waitingFor, !waiting.isEmpty {
                        Text("Ожидает: " + waiting.joined(separator: ", ")).tfText(.body)
                    }
                    if r.actionEnum == .switchProvider || r.actionEnum == .fixConfig {
                        NavigationLink("Открыть настройки моделей", value: AppRoute.runtimeProviders)
                            .disabled(!canAct || !compatible)
                    } else {
                        ActionBar(resolution: r, blockedByVersionMismatch: !compatible, enabled: canAct) { _ in
                            if r.canRestartStep {
                                restartTarget = r
                                reason = ""
                                showRestart = true
                            } else {
                                onOpenTaskControls()
                            }
                        }
                    }
                    Button("Подробности состояния") { showDetails = true }
                }
            }
            if let actionError { Section { Text(actionError).tfText(.body) } }
            if performingAction { TFLoading(.inline) }
            if let updated = state.lastUpdatedAt {
                Section { Text("Обновлено \(updated.formatted(date: .omitted, time: .shortened))").tfText(.meta) }
            }
        }
        .tfScreenBackground()
        // Плоский список (02.11.2026): серые подложки секций прятали текст и
        // превращали окно в набор серых блоков — здесь нужен плоский текст.
        .listStyle(.plain)
        .refreshable { await refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(max(1, refreshIntervalSeconds))) }
                catch { return }
            }
        }
        .sheet(isPresented: $showDetails) {
            ResolutionDetailsSheet(resolution: selected)
        }
        .sheet(isPresented: Binding(
            get: { executorSlotID != nil },
            set: { if !$0 { executorSlotID = nil } }
        )) {
            if let executorSlotID {
                ExecutorWindow(taskID: taskId, subtaskID: executorSlotID)
            }
        }
        .sheet(isPresented: Binding(
            get: { taskChatID != nil },
            set: { if !$0 { taskChatID = nil } }
        )) {
            if let taskChatID { TaskChatSheet(chatID: taskChatID) }
        }
        .alert("Перезапустить шаг?", isPresented: $showRestart) {
            TextField("Причина перезапуска", text: $reason)
            Button("Перезапустить", role: .destructive) {
                guard let target = restartTarget else { return }
                Task { await restart(target) }
            }
            .disabled(!canAct || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 1000)
            Button("Отмена", role: .cancel) { restartTarget = nil }
        } message: {
            Text("\(restartTarget?.displayTitle ?? "Выбранный шаг"): текущая попытка будет остановлена, затем запущена новая. Другие шаги не перезапускаются.")
        }
    }

    @MainActor private func refresh() async {
        guard !refreshing, !performingAction else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let items = try await APIClient().fetchTaskResolutions(taskId: taskId)
            guard !Task.isCancelled else { return }
            state.apply(resolutions: items, contractVersion: items.first?.contractVersion)
            state.pruneStaleNodes(olderThan: Date().addingTimeInterval(-300))
            if let selectedID, !state.nodes.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            if !Task.isCancelled { state.applyFailure(error.localizedDescription) }
        }
        // Сводка по исполнителям — отдельным запросом и без фатальности:
        // её отсутствие (старый сервер) не ломает координацию, нужен только
        // кнопке «Написать оркестратору».
        if let summary = try? await APIClient().taskExecutorSummary(taskId: taskId) {
            executorSummary = summary
        }
    }

    @MainActor private func restart(_ target: APIClient.CoordinationResolution) async {
        guard canAct else { return }
        performingAction = true
        actionError = nil
        do { try await APIClient().restartCoordinationStep(target, reason: reason) }
        catch { actionError = error.localizedDescription }
        performingAction = false
        restartTarget = nil
        await refresh()
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
                    Section(r.displayTitle) {
                        Text(r.displayStatus)
                        if let notes = r.notes { Text(notes).textSelection(.enabled) }
                    }
                    if !r.evidence.isEmpty {
                        Section("Основания") {
                            ForEach(Array(r.evidence.enumerated()), id: \.offset) { _, item in
                                Text(item.ref).tfText(.meta).textSelection(.enabled)
                            }
                        }
                    }
                    Section("Данные") {
                        LabeledContent("Версия", value: r.contractVersion)
                        LabeledContent("Обновлено сервером", value: r.generatedAt)
                    }
                } else { Text("Нет данных") }
            }
            .navigationTitle("Состояние шага")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
