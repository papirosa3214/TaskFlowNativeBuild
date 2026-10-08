import SwiftUI

/// Опрос выполняется только пока раскрыт текущий ход работы.
struct TaskLiveActivityView: View {
    let taskID: String
    let subtaskID: String?
    @State private var activity = ApiTaskActivity.idle
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if let text = activity.text, !text.isEmpty { Text(text).textSelection(.enabled).accessibilityIdentifier("plan-slot-live-text") }
            if !activity.actions.isEmpty {
                HStack(spacing: TFSpacing.sm) {
                    Text("Действий: \(activity.total ?? activity.actions.count)")
                    ForEach(Array(activity.actions.suffix(5))) { action in
                        Image(systemName: icon(action.kind))
                            .accessibilityLabel(action.text ?? action.kind)
                    }
                }
                .foregroundStyle(Color.tfSub)
                if activity.text == nil, let text = activity.actions.last?.text { Text(text).textSelection(.enabled) }
            } else if loaded && activity.text == nil {
                Text(errorText ?? "Новых действий пока нет").foregroundStyle(Color.tfSub)
            } else if !loaded { ProgressView() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-slot-live-content")
        .task(id: "\(taskID):\(subtaskID ?? "")") {
            activity = .idle
            loaded = false
            errorText = nil
            let api = APIClient()
            while !Task.isCancelled {
                do {
                    activity = try await api.taskActivity(taskId: taskID).forSubtask(subtaskID)
                    errorText = nil
                } catch {
                    if Task.isCancelled { return }
                    errorText = "Не удалось обновить действия"
                }
                loaded = true
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
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
