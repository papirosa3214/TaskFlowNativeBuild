import Foundation

/// Ответ владельца на конкретное сообщение. Роль так уже пишет:
/// у сообщения есть `reply_to_message_id`, в ленте — «В ответ на».
/// Здесь только выбор цели; отправка кладёт тот же идентификатор в запрос.
enum ChatOwnerReply {
    struct Target: Equatable {
        let messageID: String
        /// Текст исходного сообщения. Пустое (голос, файл) — «Вложение»,
        /// как строка «В ответ на» в ленте.
        let excerpt: String
    }

    static func target(id: String, text: String, isSessionMarker: Bool) -> Target? {
        let messageID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageID.isEmpty, !isSessionMarker else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Target(messageID: messageID, excerpt: trimmed.isEmpty ? "Вложение" : trimmed)
    }
}
