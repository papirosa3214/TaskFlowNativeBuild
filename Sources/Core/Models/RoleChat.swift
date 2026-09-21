import Foundation

extension ApiChatAttachment {
    /// Пока серверный валидатор не принимает audio/mp4, .m4a приходит как octet-stream.
    var isVoiceRecording: Bool {
        mime?.hasPrefix("audio/") == true || fileName.lowercased().hasSuffix(".m4a")
    }
}

/// Отдельный чат с ролями; старые каналы owner/agents имеют другой контракт.
public struct RoleChat: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let kind: String
    public let createdBy: String
    public let taskID: String?
    public let members: [RoleChatMember]
    public let lastMessage: RoleChatPreview?
    /// Непрочитанных у ТЕКУЩЕГО пользователя (миграция 055, отметка на
    /// участнике чата). Опционально: сервер до этой правки поля не слал, и
    /// старый ответ не должен ронять декодирование.
    public let unreadCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, members
        case createdBy = "created_by"
        case taskID = "task_id"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
    }

    public var unread: Int { unreadCount ?? 0 }

    /// Собеседники — участники без текущего пользователя. В личке это ровно
    /// один человек/роль, в группе — весь состав (он же идёт в заголовок).
    public func others(excluding userID: String?) -> [RoleChatMember] {
        members.filter { $0.id != userID }
    }

    public func displayTitle(excluding userID: String?) -> String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        // Сервер может вернуть пустое название группы: перечисляем роли без владельца.
        let names = others(excluding: userID)
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? (kind == "group" ? "Групповой чат" : "Чат") : names.joined(separator: ", ")
    }
}

public struct RoleChatMember: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let avatarColor: String?
    public let avatarURL: String?
    public let initials: String?

    enum CodingKeys: String, CodingKey {
        case id, name, initials
        case avatarColor = "avatar_color"
        case avatarURL = "avatar_url"
    }
}

public struct RoleChatPreview: Decodable, Sendable {
    public let text: String
    public let fromUserID: String?
    /// Имя отправителя — превью строки списка идёт с ним («QA: проверка
    /// прошла»); у личных чатов подпись не нужна.
    public let fromUserName: String?
    public let createdAt: String?
    /// Сколько вложений в последнем сообщении. Голосовое и файл текстом не
    /// читаются (у голосового текста может не быть вовсе), поэтому строка
    /// списка показывает «Голосовое»/«Файл» вместо пустоты.
    public let attachmentCount: Int?
    public let audioCount: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case createdAt = "created_at"
        case attachmentCount = "attachment_count"
        case audioCount = "audio_count"
    }

    /// Что показывать в строке списка: текст, иначе — иконка вложения.
    public var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if (audioCount ?? 0) > 0 { return "Голосовое сообщение" }
        if (attachmentCount ?? 0) > 0 { return "Файл" }
        return ""
    }
}

/// `/chats/:id/messages` возвращает те же поля, что общий чат, но channel=chat.
public struct RoleChatMessage: Decodable, Identifiable, Sendable {
    public let id: String
    public let chatID: String?
    public let fromUserID: String?
    public let fromUserName: String?
    public let fromUserColor: String?
    public let fromUserAvatarURL: String?
    public let fromUserInitials: String?
    public let text: String
    public let createdAt: String?
    public let attachments: [ApiChatAttachment]?

    enum CodingKeys: String, CodingKey {
        case id, text, attachments
        case chatID = "chat_id"
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserColor = "from_user_color"
        case fromUserAvatarURL = "from_user_avatar_url"
        case fromUserInitials = "from_user_initials"
        case createdAt = "created_at"
    }
}
