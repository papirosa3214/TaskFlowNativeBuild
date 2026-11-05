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

/// Слот задачи в чате: несколько слотов одной роли различаются номером.
public struct RoleChatSlot: Decodable, Equatable, Sendable {
    public let subtaskID: String
    public let roleID: String
    public let label: String
    public let state: String?

    enum CodingKeys: String, CodingKey {
        case subtaskID = "subtask_id"
        case roleID = "role_id"
        case label, state
    }

    /// Слоты роли с номером. Единственный слот роли адресуется по её имени.
    public static func numbered(for roleID: String, in slots: [RoleChatSlot]?) -> [RoleChatSlot] {
        let own = (slots ?? []).filter { $0.roleID == roleID }
        return own.count > 1 ? own : []
    }
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
    public let branchOfChatID: String?

    public init(id: String, kind: String, roomKind: String?, parentChatID: String?, projectID: String?,
                otherMemberIDs: [String], lastActivity: String?, branchOfChatID: String? = nil) {
        self.id = id
        self.kind = kind
        self.roomKind = roomKind
        self.parentChatID = parentChatID
        self.projectID = projectID
        self.otherMemberIDs = otherMemberIDs
        self.lastActivity = lastActivity
        self.branchOfChatID = branchOfChatID
    }
}

/// Строка списка сессий: чат и линии дерева слева от него.
public struct RoleSessionRow: Equatable, Sendable {
    /// Что нарисовано на одном уровне вложенности.
    public enum Line: Equatable, Sendable {
        /// Пусто: ветка этого уровня уже закончилась.
        case blank
        /// Вертикаль идёт дальше вниз, к следующей ветке.
        case through
        /// Отвод к строке, ниже есть ещё ветки.
        case branch
        /// Отвод к последней ветке.
        case lastBranch
    }

    public let id: String
    /// Пусто — сессия верхнего уровня.
    public let lines: [Line]
}

/// Сессии выбранного пункта панели: плоско, свежие сверху, ветки — деревом под
/// своей сессией (владелец 05.11.2026). Топики живут внутри чата проекта, лички
/// ролей показаны отдельно.
public enum RoleSessionList {
    public static func select(_ candidates: [RoleSessionCandidate], scope: RoleSessionScope) -> [String] {
        rows(candidates, scope: scope).map(\.id)
    }

    public static func rows(_ candidates: [RoleSessionCandidate], scope: RoleSessionScope) -> [RoleSessionRow] {
        let visible = sorted(candidates.filter { belongs($0, to: scope) })
        let ids = Set(visible.map(\.id))
        let parent: (RoleSessionCandidate) -> String? = { chat in
            guard let id = chat.branchOfChatID, ids.contains(id), id != chat.id else { return nil }
            return id
        }
        let children = Dictionary(grouping: visible.filter { parent($0) != nil }, by: { parent($0)! })
        var result: [RoleSessionRow] = []
        func append(_ chat: RoleSessionCandidate, prefix: [RoleSessionRow.Line], last: Bool?) {
            let own: [RoleSessionRow.Line] = last.map { prefix + [$0 ? .lastBranch : .branch] } ?? []
            result.append(RoleSessionRow(id: chat.id, lines: own))
            let next: [RoleSessionRow.Line] = last.map { prefix + [$0 ? .blank : .through] } ?? []
            let branches = children[chat.id] ?? []
            for (index, branch) in branches.enumerated() {
                append(branch, prefix: next, last: index == branches.count - 1)
            }
        }
        for root in visible where parent(root) == nil {
            append(root, prefix: [], last: nil)
        }
        return result
    }

    /// Группа проекта, к которой относится чат: сам чат проекта или родитель
    /// топика. `nil` — чат вне проекта, полоски топиков у него нет.
    public static func projectGroupID(chatID: String, parentChatID: String?, projectID: String?) -> String? {
        if let parentChatID { return parentChatID }
        return projectID == nil ? nil : chatID
    }

    /// Время с сервера — строка «ГГГГ-ММ-ДД ЧЧ:ММ:СС»: порядок строк совпадает
    /// с порядком дат. Без сообщений — в конец.
    private static func sorted(_ chats: [RoleSessionCandidate]) -> [RoleSessionCandidate] {
        chats.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.lastActivity ?? ""
                let right = rhs.element.lastActivity ?? ""
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }

    private static func belongs(_ chat: RoleSessionCandidate, to scope: RoleSessionScope) -> Bool {
        if chat.roomKind == "dm" || chat.parentChatID != nil { return false }
        let isGroup = chat.roomKind == "common" || chat.kind == "group" || chat.otherMemberIDs.count > 1
        switch scope {
        case .groups: return isGroup
        case .role(let id): return !isGroup && chat.otherMemberIDs == [id]
        }
    }
}
