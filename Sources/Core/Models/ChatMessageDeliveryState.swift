import Foundation

/// Различение «сообщение сохранено» и «передано исполнителю» в ленте
/// (карточка b504958a, контракт §10). Считает сервер по очереди доставки и
/// отдаёт в поле `queue_delivery_state`. Признак несёт СООБЩЕНИЕ ВЛАДЕЛЬЦА,
/// которому роль должна ответить: у ответа роли доставки «исполнителю» нет
/// вовсе, и прежний код навешивал на каждый ответ роли «Сохранено».
public enum ChatMessageDeliveryState: String, Decodable, Sendable, Equatable {
    /// Строка есть, в очередь на передачу ещё не попала.
    case saved
    /// Стоит в очереди и ждёт своей передачи.
    case queued
    /// Передано в ход исполнителя.
    case accepted
    /// Передача отменена или ход вытеснен: сообщение осталось только текстом.
    case stale

    public var label: String {
        switch self {
        case .saved: "Сохранено"
        case .queued: "В очереди"
        case .accepted: "Передано исполнителю"
        case .stale: "Не передано"
        }
    }

    public var symbol: String {
        switch self {
        case .saved: "tray.and.arrow.down"
        case .queued: "clock"
        case .accepted: "paperplane.fill"
        case .stale: "exclamationmark.triangle"
        }
    }

    /// Требует внимания владельца: сообщение не дошло до исполнения.
    public var isProblem: Bool { self == .stale }
}

/// Где показывать признак доставки (карточка b504958a, контракт §10).
///
/// Значок — под сообщением владельца: «Сохранено» значит, что сообщение
/// лежит в ленте, «Передано исполнителю» — что роль взяла его в работу.
/// Отдельная функция, а не условие в экране: правило проверяется тестом.
public enum ChatDeliveryBadgePolicy {
    /// Признак доставки показывается только под своим сообщением.
    ///
    /// - Parameters:
    ///   - message: сообщение ленты.
    ///   - isOwnMessage: сообщение отправлено текущим пользователем.
    ///   - isAgentReply: сообщение от роли — доставки «исполнителю» у него нет.
    public static func badge(
        for message: RoleChatMessage,
        isOwnMessage: Bool,
        isAgentReply: Bool
    ) -> ChatMessageDeliveryState? {
        guard isOwnMessage, !isAgentReply else { return nil }
        return message.queueDeliveryState
    }
}

#if DEBUG
extension ChatMessageDeliveryState {
    /// Набор для отладочной галереи кадров: все состояния по порядку.
    static let allCasesForPreview: [ChatMessageDeliveryState] = [.saved, .queued, .accepted, .stale]
}
#endif
