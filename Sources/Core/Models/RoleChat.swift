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
    /// Название задачи, к которой привязан чат (`nil` — свободный). Нужно
    /// пометкой в строке списка: по ней видно, какой чат за какой задачей.
    public let taskTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, members
        case createdBy = "created_by"
        case taskID = "task_id"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case taskTitle = "task_title"
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

/// Чат, привязанный к задаче — карточка отдаёт их списком, чтобы дать переход
/// в переписку. Сам чат в карточке не рисуется: для него есть свой экран
/// (владелец 21.09.2026, LOCK-195).
public struct ApiTaskChat: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String?
    public let kind: String?
    public let membersCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, kind
        case membersCount = "members_count"
    }

    /// Что показать в строке карточки: название чата, иначе — по составу.
    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return kind == "group" ? "Групповой чат" : "Чат"
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
    /// Задача, которую роль создала этим ходом (владелец 25.09.2026,
    /// docs/ПЛАН Супер Секретарь/, этап 2) — есть значение → вместо текста
    /// рисуется карточка (см. RoleChatsScreen).
    public let taskID: String?
    public let taskTitle: String?
    /// Быстрые ответы (владелец 25.09.2026, docs/ПЛАН Супер Секретарь/) —
    /// 2-4 коротких варианта, которые предложила роль вместо того, чтобы
    /// печатать руками. Только у последнего сообщения роли есть смысл.
    public let quickReplies: [String]?
    /// Разделитель «новая сессия» (владелец 25.09.2026) — рисуется не
    /// пузырём, а меткой посередине; сама история при сбросе сессии не
    /// удаляется, разделитель просто показывает границу.
    public let isSessionMarker: Bool
    /// Шаги хода роли, которые привели к этому ответу (владелец 27.09.2026,
    /// живой ход как в Claude Code) — рисуются свёрнутой строкой «N шагов ·
    /// M с» над текстом. `nil` — ход без шагов или сообщение не от роли.
    public let steps: RoleChatSteps?

    enum CodingKeys: String, CodingKey {
        case id, text, attachments, steps
        case chatID = "chat_id"
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserColor = "from_user_color"
        case fromUserAvatarURL = "from_user_avatar_url"
        case fromUserInitials = "from_user_initials"
        case createdAt = "created_at"
        case taskID = "task_id"
        case taskTitle = "task_title"
        case quickReplies = "quick_replies"
        case isSessionMarker = "is_session_marker"
    }
}

/// Шаги хода роли, сохранённые вместе с ответом (`chat_messages.steps`).
public struct RoleChatSteps: Decodable, Sendable, Equatable {
    public let durationMs: Int
    public let items: [RoleChatLiveItem]

    enum CodingKeys: String, CodingKey {
        case items
        case durationMs = "duration_ms"
    }

    public var stepCount: Int { items.filter(\.isStep).count }
}

/// Элемент хода роли — кусок текста или шаг (вызов инструмента). Сервер
/// отдаёт голое имя инструмента и короткую подпись из аргументов (путь,
/// команда); действие по-русски выбирает клиент (`RoleLiveStepKind`).
public enum RoleChatLiveItem: Decodable, Sendable, Equatable, Identifiable {
    case text(String)
    case step(RoleChatLiveStep)

    public var id: String {
        switch self {
        case .text(let text): return "text-\(text.hashValue)"
        case .step(let step): return step.id
        }
    }

    public var isStep: Bool {
        if case .step = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(String.self, forKey: .kind) == "text" {
            self = .text(try container.decode(String.self, forKey: .text))
        } else {
            self = .step(try RoleChatLiveStep(from: decoder))
        }
    }
}

public struct RoleChatLiveStep: Decodable, Sendable, Equatable {
    public enum Status: String, Decodable, Sendable {
        case running, done, error
    }

    public let id: String
    public let tool: String
    public let detail: String?
    public let status: Status

    public init(id: String, tool: String, detail: String?, status: Status) {
        self.id = id
        self.tool = tool
        self.detail = detail
        self.status = status
    }

    private enum CodingKeys: String, CodingKey { case id, tool, detail, status }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tool = try container.decode(String.self, forKey: .tool)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        // Незнакомый статус (сервер новее клиента) — считаем шаг идущим,
        // а не роняем весь снимок хода.
        let raw = try container.decodeIfPresent(String.self, forKey: .status) ?? "running"
        status = Status(rawValue: raw) ?? .running
    }
}

/// Идущий сейчас ход роли в чате (`chats:live`, `GET /chats/:id/live`):
/// текст ответа растёт по словам, между кусками текста — шаги.
public struct RoleChatLiveTurn: Decodable, Sendable, Equatable {
    public let chatID: String
    public let userID: String
    public let name: String
    public let startedAt: String?
    public let items: [RoleChatLiveItem]

    enum CodingKeys: String, CodingKey {
        case name, items
        case chatID = "chat_id"
        case userID = "user_id"
        case startedAt = "started_at"
    }

    /// Когда ход начался — для счётчика «идёт 42 с».
    public var startDate: Date? {
        guard let startedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: startedAt) ?? ISO8601DateFormatter().date(from: startedAt)
    }
}
