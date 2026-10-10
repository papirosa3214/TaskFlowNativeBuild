import Foundation

struct SubtaskWorkPlan: Decodable, Sendable, Equatable {
    let subtaskID: String
    let revision: Int
    let items: [Item]
    let updatedAt: String
    struct Item: Decodable, Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let state: State
        enum State: String, Decodable, Sendable {
            case pending, inProgress = "in_progress", done
            var label: String {
                switch self {
                case .pending: "Ожидает"
                case .inProgress: "Сейчас"
                case .done: "Выполнено"
                }
            }
            var symbol: String {
                switch self {
                case .pending: "square"
                case .inProgress: "play.square"
                case .done: "checkmark.square.fill"
                }
            }
        }
    }
    enum CodingKeys: String, CodingKey {
        case subtaskID = "subtask_id", revision, items
        case updatedAt = "updated_at"
    }
    var doneCount: Int { items.filter { $0.state == .done }.count }
}
struct SubtaskWorkPlanResponse: Decodable { let plan: SubtaskWorkPlan? }
