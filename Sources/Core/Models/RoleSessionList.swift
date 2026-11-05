import Foundation

/// Что выбрано на панели у края раздела «Чаты»: роль или групповые чаты.
public enum RoleSessionScope: Equatable, Sendable {
    case role(String)
    case groups

    private static let groupsKey = "groups"
    public var stored: String {
        switch self {
        case .role(let id): id
        case .groups: Self.groupsKey
        }
    }
    public init(stored: String) {
        self = stored == Self.groupsKey ? .groups : .role(stored)
    }
}

/// Занятое окно контекста сессии для строки списка.
public struct RoleChatContextUsage: Decodable, Equatable, Sendable {
    public let tokens: Int
    public let contextWindow: Int

    public init(tokens: Int, contextWindow: Int) {
        self.tokens = tokens
        self.contextWindow = contextWindow
    }

    enum CodingKeys: String, CodingKey {
        case tokens
        case contextWindow = "context_window"
    }

    public var percent: Int? {
        guard contextWindow > 0 else { return nil }
        return Int((Double(tokens) / Double(contextWindow) * 100).rounded())
    }
    public var label: String? { percent.map { "Контекст \($0)%" } }
}

/// Данные чата, которые решают, в какой список он попадёт.
public struct RoleSessionCandidate: Sendable {
    public let id: String
    public let kind: String
    public let roomKind: String?
    public let parentChatID: String?
    public let projectID: String?
    public let otherMemberIDs: [String]
    public let lastActivity: String?

    public init(id: String, kind: String, roomKind: String?, parentChatID: String?, projectID: String?,
                otherMemberIDs: [String], lastActivity: String?) {
        self.id = id
        self.kind = kind
        self.roomKind = roomKind
        self.parentChatID = parentChatID
        self.projectID = projectID
        self.otherMemberIDs = otherMemberIDs
        self.lastActivity = lastActivity
    }
}

/// Сессии выбранного пункта панели: плоско, свежие сверху (владелец 05.11.2026).
/// Общая, лички ролей и группы проектов живут в своих местах и сюда не входят.
public enum RoleSessionList {
    public static func select(_ candidates: [RoleSessionCandidate], scope: RoleSessionScope) -> [String] {
        candidates
            .filter { belongs($0, to: scope) }
            .enumerated()
            .sorted { lhs, rhs in
                // Время с сервера — строка «ГГГГ-ММ-ДД ЧЧ:ММ:СС»: порядок строк
                // совпадает с порядком дат. Без сообщений — в конец.
                let left = lhs.element.lastActivity ?? ""
                let right = rhs.element.lastActivity ?? ""
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element.id)
    }

    private static func belongs(_ chat: RoleSessionCandidate, to scope: RoleSessionScope) -> Bool {
        if chat.roomKind == "common" || chat.roomKind == "dm" { return false }
        if chat.parentChatID == nil && chat.projectID != nil { return false }
        let isGroup = chat.kind == "group" || chat.otherMemberIDs.count > 1
        switch scope {
        case .groups: return isGroup
        case .role(let id): return !isGroup && chat.otherMemberIDs == [id]
        }
    }
}
