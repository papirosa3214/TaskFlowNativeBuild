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
/// Варианты принадлежат СВОЕМУ сообщению: они рисуются под тем сообщением
/// роли, которое их предложило. Раньше правило брало последнее СЫРОЕ
/// сообщение и дополнительно требовало совпадения с последним видимым:
/// если следом лежала скрытая служебная строка координации или дубль
/// доигранного живого хода, проверка не проходила — вопрос стоял прямо над
/// плашками, а кнопок не было вовсе. Сейчас привязка к своему сообщению,
/// а список для сравнения — уже отфильтрованный (видимые сообщения).
///
/// Собственный ответ владельца снимает актуальность: после него варианты
/// вопроса больше не показываются.
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
        // Ответ владельца ПОЗЖЕ вопроса снимает актуальность вариантов:
        // человек уже ответил, плашки больше не нужны.
        if let index = visibleMessages.firstIndex(where: { $0.id == message.id }),
           visibleMessages[(index + 1)...].contains(where: { $0.fromUserID == ownerID }) {
            return nil
        }
        return Array(replies.prefix(maxReplies))
    }
}
