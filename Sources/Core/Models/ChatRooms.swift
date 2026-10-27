import Foundation

/// Снимок панели «Комнаты» — `GET /api/chats/rooms` (владелец 21.10.2026).
/// Общая, личная комната каждой роли и её лички с другими ролями.
public struct ChatRoomsSnapshot: Decodable, Sendable {
    public let common: CommonRoom
    public let roles: [RoleRoom]
    /// Внешние агенты без постоянной комнаты (владелец 21.10.2026): в панели
    /// их нет, комнату заводят из меню «…». Старый сервер поля не шлёт.
    public var externalCandidates: [RoleChatMember] = []

    enum CodingKeys: String, CodingKey {
        case common, roles
        case externalCandidates = "external_candidates"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        common = try c.decode(CommonRoom.self, forKey: .common)
        roles = try c.decode([RoleRoom].self, forKey: .roles)
        externalCandidates = try c.decodeIfPresent([RoleChatMember].self, forKey: .externalCandidates) ?? []
    }

    public struct CommonRoom: Decodable, Sendable {
        public let chatID: String
        public let live: Bool
        public let lastMessage: RoomMessage?
        enum CodingKeys: String, CodingKey {
            case live
            case chatID = "chat_id"
            case lastMessage = "last_message"
        }
    }

    public struct RoleRoom: Decodable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let roleKey: String?
        public let avatarColor: String?
        public let avatarURL: String?
        public let initials: String?
        public let personalChatID: String?
        /// Роль прямо сейчас делает ход.
        public let working: Bool
        public let lastMessage: RoomMessage?
        public let dms: [DirectRoom]
        /// Ход роли в личной комнате. Старый сервер поля не шлёт.
        public var personalTurn: RoomTurn? = nil

        enum CodingKeys: String, CodingKey {
            case id, name, initials, working, dms
            case roleKey = "role_key"
            case avatarColor = "avatar_color"
            case avatarURL = "avatar_url"
            case personalChatID = "personal_chat_id"
            case lastMessage = "last_message"
            case personalTurn = "personal_turn"
        }

        /// Тот же вид участника, что в чатах: аватар рисуется общим компонентом.
        public var member: RoleChatMember {
            RoleChatMember(id: id, name: name, avatarColor: avatarColor, avatarURL: avatarURL, initials: initials, roleKey: roleKey)
        }

        /// Живые лички роли — по ним горит облачко.
        public var liveDMs: [DirectRoom] { dms.filter(\.live) }
    }

    public struct DirectRoom: Decodable, Identifiable, Sendable {
        public let chatID: String
        public let peerID: String?
        /// Ключ пары — одинаковый у обеих ролей, по нему один цвет облачка.
        public let pair: String
        public let live: Bool
        public let lastMessage: RoomMessage?
        public var turn: RoomTurn? = nil
        public var id: String { chatID }

        enum CodingKeys: String, CodingKey {
            case pair, live, turn
            case chatID = "chat_id"
            case peerID = "peer_id"
            case lastMessage = "last_message"
        }
    }

    public struct RoomMessage: Decodable, Sendable {
        public let text: String
        public let createdAt: String?
        public let fromUserID: String?
        enum CodingKeys: String, CodingKey {
            case text
            case createdAt = "created_at"
            case fromUserID = "from_user_id"
        }
    }

    public func role(_ id: String?) -> RoleRoom? {
        guard let id else { return nil }
        return roles.first { $0.id == id }
    }
}

/// Ход роли в комнате для строки списка (владелец 27.10.2026): идёт ход —
/// аватарка играет ролик; после хода точка — ответила, отвалилась или
/// кончился лимит. Итог сервер гасит сам, когда владелец открыл комнату.
public struct RoomTurn: Decodable, Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case answered, failed, limit
    }

    public let running: Bool
    /// `nil` — итога нет или сервер прислал незнакомый.
    public let outcome: Outcome?

    public init(running: Bool, outcome: Outcome?) {
        self.running = running
        self.outcome = outcome
    }

    enum CodingKeys: String, CodingKey { case running, outcome }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome).flatMap(Outcome.init(rawValue:))
    }
}
