import Foundation

/// Состояние плана целиком — считает сервер (контракт §3.3, коммит d9ab378a).
enum ChatWorkPlanStatus: String, Decodable, Sendable, Equatable {
    case active, finished, stopped

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatWorkPlanStatus(rawValue: raw) ?? .active
    }
}

/// Почему план остановлен. Ставит только сервер.
enum ChatWorkPlanStopReason: String, Decodable, Sendable, Equatable {
    case ownerStop = "owner_stop"
    case budgetExhausted = "budget_exhausted"
    case sessionReset = "session_reset"
    case error

    var label: String {
        switch self {
        case .ownerStop: "остановил владелец"
        case .budgetExhausted: "исчерпаны лимиты"
        case .sessionReset: "сессия сброшена"
        case .error: "ошибка"
        }
    }
}

/// Рабочий чек-лист роли в чатовой сессии — `GET /api/chats/:id/work-plans`
/// (21.10.2026). С 25.10.2026 (карточка b504958a) состояние каждого пункта и
/// текущий пункт считает сервер: клиент их не вычисляет, а только рисует.
/// Старый сервер полей `status`/`stop_reason`/`current_item_id` не присылает —
/// тогда план считается активным (совместимость).
struct ChatWorkPlan: Decodable, Sendable, Equatable, Identifiable {
    let chatID: String
    let roleID: String
    let revision: Int
    let items: [SubtaskWorkPlan.Item]
    let updatedAt: String
    let status: ChatWorkPlanStatus
    let stopReason: ChatWorkPlanStopReason?
    let stoppedAt: String?
    let currentItemID: String?

    init(
        chatID: String,
        roleID: String,
        revision: Int,
        items: [SubtaskWorkPlan.Item],
        updatedAt: String,
        status: ChatWorkPlanStatus = .active,
        stopReason: ChatWorkPlanStopReason? = nil,
        stoppedAt: String? = nil,
        currentItemID: String? = nil
    ) {
        self.chatID = chatID
        self.roleID = roleID
        self.revision = revision
        self.items = items
        self.updatedAt = updatedAt
        self.status = status
        self.stopReason = stopReason
        self.stoppedAt = stoppedAt
        self.currentItemID = currentItemID
    }

    var id: String { roleID }
    var doneCount: Int { items.filter { $0.state == .done }.count }
    var isStopped: Bool { status == .stopped }

    /// Текущий пункт — тот, что назвал сервер; без поля (старый сервер) —
    /// первый `in_progress` из пунктов.
    var current: SubtaskWorkPlan.Item? {
        if let currentItemID, let named = items.first(where: { $0.id == currentItemID }) {
            return named
        }
        return items.first { $0.state == .inProgress }
    }

    /// Строка над полем ввода: что за план, сколько сдано и где сейчас дело.
    /// Остановленный план вместо «сейчас» называет причину — иначе владелец
    /// видел бы вечный текущий пункт там, где работа уже прекращена.
    func summary(roleName: String) -> String {
        var text = isStopped ? "План остановлен · \(roleName)" : "План · \(roleName)"
        text += " · \(doneCount) из \(items.count)"
        if isStopped {
            if let stopReason { text += " · \(stopReason.label)" }
        } else if let current {
            text += " · сейчас: \(current.title)"
        }
        return text
    }

    enum CodingKeys: String, CodingKey {
        case revision, items, status
        case chatID = "chat_id"
        case roleID = "role_id"
        case updatedAt = "updated_at"
        case stopReason = "stop_reason"
        case stoppedAt = "stopped_at"
        case currentItemID = "current_item_id"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chatID = try c.decode(String.self, forKey: .chatID)
        roleID = try c.decode(String.self, forKey: .roleID)
        revision = try c.decode(Int.self, forKey: .revision)
        items = try c.decode([SubtaskWorkPlan.Item].self, forKey: .items)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        status = try c.decodeIfPresent(ChatWorkPlanStatus.self, forKey: .status) ?? .active
        stopReason = try c.decodeIfPresent(ChatWorkPlanStopReason.self, forKey: .stopReason)
        stoppedAt = try c.decodeIfPresent(String.self, forKey: .stoppedAt)
        currentItemID = try c.decodeIfPresent(String.self, forKey: .currentItemID)
    }
}

struct ChatWorkPlansResponse: Decodable { let plans: [ChatWorkPlan] }

extension ChatWorkPlan {
    /// План роли из события `chat:work_plan` ложится в список полосы без
    /// повторного запроса (владелец 27.10.2026). Сброс плана (пустые пункты)
    /// убирает строку роли; устаревшая ревизия список не меняет.
    /// `nil` — событие не этого чата или не разобрано: тогда полоса стоит как была.
    static func applyingEvent(_ payload: JSONValue, chatID: String, to plans: [ChatWorkPlan]) -> [ChatWorkPlan]? {
        guard case .object(let fields) = payload, fields["chat_id"]?.stringValue == chatID,
              let plan = fields["plan"], let data = try? JSONEncoder().encode(plan) else { return nil }
        struct Reset: Decodable { let role_id: String; let items: [JSONValue] }
        if let reset = try? JSONDecoder().decode(Reset.self, from: data), reset.items.isEmpty {
            return plans.filter { $0.roleID != reset.role_id }
        }
        guard let incoming = try? JSONDecoder().decode(ChatWorkPlan.self, from: data) else { return nil }
        // Закрытый план (сдан целиком или закрыт стопом владельца) полоску не
        // занимает — иначе он висел бы мусором (владелец 11.11.2026).
        guard incoming.status == .active else { return plans.filter { $0.roleID != incoming.roleID } }
        var result = plans
        if let index = result.firstIndex(where: { $0.roleID == incoming.roleID }) {
            if result[index].revision <= incoming.revision { result[index] = incoming }
        } else {
            result.append(incoming)
        }
        return result
    }
}
