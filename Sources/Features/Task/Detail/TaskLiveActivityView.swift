import SwiftUI

/// Живой ход по WebSocket; REST восстанавливает снимок при открытии и разрыве.
struct TaskLiveActivityView: View {
    let taskID: String
    let subtaskID: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var live: TaskLiveTurn?
    @State private var realtime = RealtimeClient()
    @State private var activity = ApiTaskActivity.idle
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if let live {
                RoleTranslateButton(items: live.turn.items)
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
                } else if !loaded { ProgressView() }
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
            realtime.onEvent = { event in
                if case .taskLive(let turn) = event,
                   turn.taskID == taskID, turn.subtaskID == subtaskID {
                    live = turn
                }
            }
            realtime.connect()
        }
        .task(id: "\(taskID):\(subtaskID ?? ""):\(scenePhase):\(realtime.revision(for: taskID)):\(realtime.activityRevisions[taskID] ?? 0)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_ACTION_LABELS_PREVIEW"] == "1" { return }
            #endif
            guard scenePhase == .active else { return }
            await restoreSnapshot()
        }
        .onDisappear { realtime.disconnect(); realtime.onEvent = nil }
    }

    private func restoreSnapshot() async {
        let api = APIClient()
        if let turns = try? await api.taskLiveTurns(taskID: taskID),
           let turn = turns.first(where: { $0.subtaskID == subtaskID }) {
            if live?.turn.startedAt == nil || (turn.turn.startedAt ?? "") > (live?.turn.startedAt ?? "") {
                live = turn
            }
        }
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
