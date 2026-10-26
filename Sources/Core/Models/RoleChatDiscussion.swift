import Foundation

/// Обсуждение работающей карточки — отдельная сущность со своим
/// жизненным циклом (сервер: `GET /api/discussions/:id`, миграция
/// 175_task_discussions, карточка 252c400e, этапы 3–4).
///
/// Обсуждение — не «ещё один чат»: у него есть состояние (открыто → закрывается
/// → закрыто) и состояние доставки итога исполнителю. Владелец видит оба.
public struct RoleChatDiscussion: Decodable, Sendable, Equatable {

    /// Состояние обсуждения. Значение, которого клиент не знает, читается как
    /// «идёт» — старый клиент не должен ломаться на новом сервере.
    public enum State: String, Decodable, Sendable, Equatable {
        case open = "open"
        case closing = "closing"
        case closed = "closed"
        case unknown = "unknown"

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw) ?? .unknown
        }
    }

    /// Доставка итога исполнителю.
    public enum DeliveryState: String, Decodable, Sendable, Equatable {
        case notReady = "not_ready"
        case awaiting = "awaiting"
        case delivered = "delivered"
        case failed = "failed"
        case noRecipient = "no_recipient"
        case unknown = "unknown"

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = DeliveryState(rawValue: raw) ?? .unknown
        }
    }

    public let discussionID: String
    public let chatID: String
    public let taskID: String
    public let subtaskID: String
    public let state: State
    public let deliveryState: DeliveryState
    public let handoffID: String?
    public let summaryID: String?
    public let messages: Int
    public let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case discussionID = "discussion_id"
        case chatID = "chat_id"
        case taskID = "task_id"
        case subtaskID = "subtask_id"
        case state
        case deliveryState = "delivery_state"
        case handoffID = "handoff_id"
        case summaryID = "summary_id"
        case messages
        case acceptedAt = "accepted_at"
    }

    /// Короткий статус для владельца: что сейчас с обсуждением.
    public var statusTitle: String {
        switch (state, deliveryState) {
        case (.closed, .delivered):
            return "Итог получен исполнителем"
        case (.closed, .awaiting), (.closed, .notReady):
            return "Итог сохранён, ожидает доставки"
        case (.closed, .failed):
            return "Итог не доставлен"
        case (.closed, .noRecipient):
            return "Итог сохранён, получатель не найден"
        case (.closing, _):
            return "Обсуждение закрывается"
        case (.open, _):
            return "Обсуждение открыто"
        default:
            return "Обсуждение"
        }
    }

    /// Пояснение под статусом — что делать владельцу дальше.
    public var statusDetail: String? {
        switch (state, deliveryState) {
        case (.closed, .delivered):
            return "Исполнитель получил итог обсуждения."
        case (.closed, .awaiting), (.closed, .notReady):
            return "Итог сохранён. Он уйдёт исполнителю, как только тот возьмёт этап."
        case (.closed, .failed):
            return "Доставка итога не прошла. Обсуждение можно закрыть повторно."
        case (.closed, .noRecipient):
            return "Этап закрыт или сменился исполнитель. Итог сохранён, но ждать доставки некому."
        case (.closing, _):
            return "Обсуждение закрывается: готовится итог."
        default:
            return nil
        }
    }

    /// Итог ждёт адресата: видно владельцу как «ожидает доставки».
    public var isAwaitingDelivery: Bool {
        state == .closed && (deliveryState == .awaiting || deliveryState == .notReady)
    }
}
