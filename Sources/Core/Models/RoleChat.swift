import Foundation

/// Отдельный чат с ролями; старые каналы owner/agents имеют другой контракт.
public struct RoleChat: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let kind: String
    public let createdBy: String
    public let members: [RoleChatMember]
    public let lastMessage: RoleChatPreview?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, members
        case createdBy = "created_by"
        case lastMessage = "last_message"
    }

    public func displayTitle(excluding userID: String?) -> String {
        if let title, !title.isEmpty { return title }
        let names = members.filter { $0.id != userID }.map(\.name)
        return names.isEmpty ? "Чат" : names.joined(separator: ", ")
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

    enum CodingKeys: String, CodingKey {
        case text
        case fromUserID = "from_user_id"
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

    enum CodingKeys: String, CodingKey {
        case id, text
        case chatID = "chat_id"
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserColor = "from_user_color"
        case fromUserAvatarURL = "from_user_avatar_url"
        case fromUserInitials = "from_user_initials"
        case createdAt = "created_at"
    }
}
