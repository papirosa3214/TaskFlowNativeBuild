import SwiftUI

/// Живой ход по WebSocket; REST восстанавливает снимок при открытии и разрыве.
struct TaskLiveActivityView: View {
    let taskID: String
    let subtaskID: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var live: TaskLiveTurn?
    /// Общий канал приложения: свой сокет на каждый экран шторки роли давал
    /// десятки переподключений в минуту (видно в журнале сервера).
    @Environment(RealtimeClient.self) private var realtime
    @State private var observerID: UUID?
    @State private var activity = ApiTaskActivity.idle
    @State private var errorText: String?
    @State private var loaded = false
    /// Список действий протухает от событий активности и обновляется циклом
    /// ниже — не чаще раза в две секунды.
    @State private var refreshState = LiveActivityRefreshState()

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Статистика действий роли по журналу сервера. Она переживает
            // буфер в памяти, поэтому «почему оно падало» видно и спустя
            // время: сколько операций, сколько успешных, сколько ошибок и
            // по каким (владелец 02.11.2026).
            if let stats = activity.stats, stats.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Действий роли: \(stats.total) · успешно \(stats.ok) · ошибок \(stats.failed)")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                    ForEach(stats.failedOperations.prefix(5)) { operation in
                        Text("\(operation.operation) — ошибок \(operation.failed) из \(operation.total)")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfOrange)
                    }
                    ForEach(stats.errors.suffix(5)) { failure in
                        Text("\(failure.operation): \(failure.message)")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                            .textSelection(.enabled)
                    }
                }
                .accessibilityIdentifier("plan-slot-activity-stats")
            }
            if let live {
                RoleLiveTurnBubble(turn: live.turn, showsName: false, isComplete: live.complete, startsWithSnapshot: true)
                    .id(live.runID)
                    .accessibilityIdentifier("plan-slot-stream")
            } else {
                if let text = activity.text, !text.isEmpty { Text(text).textSelection(.enabled).accessibilityIdentifier("plan-slot-live-text") }
                if !activity.actions.isEmpty {
                    Text("Действий: \(activity.total ?? activity.actions.count)")
                        .foregroundStyle(Color.tfSub)
                    ForEach(activity.actions) { action in
                        HStack(alignment: .top, spacing: TFSpacing.sm) {
                            Image(systemName: icon(action.kind))
                                .foregroundStyle(Color.tfSub)
                                .frame(width: 18)
                            Text(action.text ?? "Выполняет действие")
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(action.date.formatted(date: .omitted, time: .standard))
                                .tfText(.meta)
                                .foregroundStyle(Color.tfSub)
                        }
                        .accessibilityIdentifier("plan-slot-action")
                    }
                } else if loaded && activity.text == nil {
                    Text(errorText ?? "Новых действий пока нет").foregroundStyle(Color.tfSub)
                } else if !loaded { TFLoading(.inline) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-slot-live-content")
        .task(id: "\(taskID):\(subtaskID ?? "")") {
            live = nil
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_ACTION_LABELS_PREVIEW"] == "1" {
                live = TaskLiveTurn.previewActions(taskID: taskID, subtaskID: subtaskID)
                loaded = true
                return
            }
            #endif
            // Подписка на общий канал: слот `onEvent` у клиента один, и его
            // держит приложение (TaskStore) — свой слот занял бы его.
            if let observerID { realtime.removeObserver(observerID) }
            observerID = realtime.addObserver { event in
                if case .taskLive(let turn) = event,
                   turn.taskID == taskID, turn.subtaskID == subtaskID {
                    live = turn
                }
                // Событие активности само ничего не перерисовывает: список
                // действий забирает цикл ниже, не чаще раза в две секунды.
                if case .taskActivity(let id, _) = event, id == taskID {
                    refreshState.markDirty()
                }
            }
        }
        // Снимок — при открытии окна, смене шага или сцены. Раньше id
        // включал ревизии живых событий, и задача перезапускалась на КАЖДОМ
        // событии: при идущем ходе это раз в секунду — два REST-запроса и
        // перерисовка окна, из-за чего прокрутка сбрасывалась наверх, а
        // владелец не мог долистать до «Прервать» (владелец 25.10.2026).
        .task(id: "\(taskID):\(subtaskID ?? ""):\(scenePhase)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_ACTION_LABELS_PREVIEW"] == "1" { return }
            #endif
            guard scenePhase == .active else { return }
            await restoreSnapshot()
        }
        // Список действий: событие только помечает его протухшим, забирает
        // отдельный цикл — не чаще раза в две секунды. Раньше задача была
        // привязана к ревизии событий, и на каждый пакет событий уходил запрос
        // и перерисовка окна (владелец 25.10.2026).
        .task(id: "\(taskID):\(subtaskID ?? ""):\(scenePhase):activity") {
            guard scenePhase == .active else { return }
            await refreshActivityLoop()
        }
        .onDisappear {
            // Сокет общий — закрывает его приложение, а мы снимаем подписку.
            if let observerID { realtime.removeObserver(observerID) }
            observerID = nil
        }
    }

    /// Цикл обновления списка действий: ждёт интервал, забирает протухшее
    /// состояние и обновляет список. Пока событий нет — запросов нет.
    private func refreshActivityLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: LiveActivityRefreshState.minimumInterval)
            guard !Task.isCancelled else { return }
            guard refreshState.takeDirty() else { continue }
            await refreshActivity()
        }
    }

    private func restoreSnapshot() async {
        let api = APIClient()
        if let turns = try? await api.taskLiveTurns(taskID: taskID),
           let turn = turns.first(where: { $0.subtaskID == subtaskID }) {
            if live?.turn.startedAt == nil || (turn.turn.startedAt ?? "") > (live?.turn.startedAt ?? "") {
                live = turn
            }
        }
        await refreshActivity()
    }

    private func refreshActivity() async {
        let api = APIClient()
        do {
            activity = try await api.taskActivity(taskId: taskID).forSubtask(subtaskID)
            errorText = nil
        } catch {
            if Task.isCancelled { return }
            errorText = "Не удалось обновить действия"
        }
        loaded = true
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "read": "book"
        case "edit": "chevron.left.forwardslash.chevron.right"
        case "write": "doc.badge.plus"
        case "search": "magnifyingglass"
        case "run": "terminal"
        case "think": "brain"
        case "web": "globe"
        case "test": "checkmark.seal"
        case "build": "hammer"
        case "git": "arrow.triangle.branch"
        default: "ellipsis"
        }
    }
}
