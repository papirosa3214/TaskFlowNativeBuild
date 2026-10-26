import Foundation

/// Сообщение, у которого могут быть быстрые варианты ответа.
///
/// Отдельный протокол, а не `RoleChatMessage` целиком: правило показа
/// вариантов проверяется тестом без симулятора и без приложения
/// (`Tools/test_chat_question.py`).
public protocol QuickReplyMessage {
    var id: String { get }
    var fromUserID: String? { get }
    /// Варианты, предложенные ролью в этом сообщении.
    var quickReplies: [String]? { get }
}

/// Правило показа быстрых вариантов ответа (26.10.2026).
///
/// Варианты принадлежат ПОСЛЕДНЕМУ ВИДИМОМУ сообщению ленты, если оно не
/// моё. Раньше правило брало последнее СЫРОЕ сообщение и дополнительно
/// требовало совпадения с последним видимым: если следом лежала скрытая
/// строка координации или дубль доигранного живого хода, проверка не
/// проходила — вопрос стоял прямо над плашками, а кнопок не было вовсе.
///
/// Поэтому список сообщений сюда передаётся уже отфильтрованным (видимым):
/// скрытые служебные строки варианты не отменяют.
public enum ChatQuickReplyPolicy {
    /// Модель иногда даёт четыре варианта — четвёртый загромождает ряд
    /// (владелец 26.09.2026).
    public static let maxReplies = 3

    /// Варианты для сообщения `message` или nil, если показывать нечего.
    ///
    /// - Parameters:
    ///   - message: сообщение, у которого ищем варианты.
    ///   - visibleMessages: сообщения ленты ПОСЛЕ фильтра (без служебных).
    ///   - ownerID: владелец. Его собственное сообщение снимает
    ///     актуальность предложенных вариантов.
    public static func replies(for message: some QuickReplyMessage,
                                in visibleMessages: [some QuickReplyMessage],
                                ownerID: String?) -> [String]? {
        guard message.fromUserID != ownerID,
              let replies = message.quickReplies, !replies.isEmpty else { return nil }
        // Варианты в силе только у последнего видимого сообщения: после него
        // либо владелец ответил (своё сообщение), либо роль предложила новое.
        guard let last = visibleMessages.last, last.id == message.id else { return nil }
        return Array(replies.prefix(maxReplies))
    }
}
