import Foundation

/// Рабочий чек-лист роли в чатовой сессии — `GET /api/chats/:id/work-plans`
/// (21.10.2026). Пункты те же, что у плана слота (`SubtaskWorkPlan.Item`).
struct ChatWorkPlan: Decodable, Sendable, Equatable, Identifiable {
    let chatID: String
    let roleID: String
    let revision: Int
    let items: [SubtaskWorkPlan.Item]
    let updatedAt: String

    var id: String { roleID }
    var doneCount: Int { items.filter { $0.state == .done }.count }
    var current: SubtaskWorkPlan.Item? { items.first { $0.state == .inProgress } }

    enum CodingKeys: String, CodingKey {
        case revision, items
        case chatID = "chat_id"
        case roleID = "role_id"
        case updatedAt = "updated_at"
    }
}

struct ChatWorkPlansResponse: Decodable { let plans: [ChatWorkPlan] }
