import Foundation

/// Реестр правил ролей (11.11.2026): какие правила сервер вкладывает ролям в
/// инструкции, кому именно и сколько раз они уже ушли.

/// Адресаты правила: всем ролям (`"all"`) или списку ролей.
public enum RoleRuleTargets: Codable, Hashable, Sendable {
    case all
    case roles([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard text == "all" else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ожидалось \"all\", пришло \(text)")
            }
            self = .all
            return
        }
        self = .roles(try container.decode([String].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all: try container.encode("all")
        case .roles(let ids): try container.encode(ids)
        }
    }

    public var isAll: Bool { if case .all = self { true } else { false } }

    public func includes(_ roleID: String) -> Bool {
        switch self {
        case .all: true
        case .roles(let ids): ids.contains(roleID)
        }
    }
}

public struct RoleRuleRole: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public struct RoleRule: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let category: String?
    public let roles: RoleRuleTargets
    public let channels: [String]
    public let `where`: String?
    public let active: Bool
    public let recommended: Bool
    public let explanation: String?
    public let deliveredUses: Int

    public enum CodingKeys: String, CodingKey {
        case id, text, category, roles, channels
        case `where`
        case active, recommended, explanation
        case deliveredUses = "delivered_uses"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        roles = try c.decodeIfPresent(RoleRuleTargets.self, forKey: .roles) ?? .all
        channels = try c.decodeIfPresent([String].self, forKey: .channels) ?? []
        `where` = try c.decodeIfPresent(String.self, forKey: .where)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        recommended = try c.decodeIfPresent(Bool.self, forKey: .recommended) ?? false
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        deliveredUses = try c.decodeIfPresent(Int.self, forKey: .deliveredUses) ?? 0
    }
}

public struct RoleRulesEnvelope: Codable, Sendable {
    public let roles: [RoleRuleRole]
    public let rules: [RoleRule]
}

/// Тело PATCH: передаются только изменённые поля.
public struct RoleRulePatch: Encodable, Sendable {
    public var active: Bool?
    public var roles: RoleRuleTargets?
    public var recommended: Bool?

    public init(active: Bool? = nil, roles: RoleRuleTargets? = nil, recommended: Bool? = nil) {
        self.active = active
        self.roles = roles
        self.recommended = recommended
    }

    enum CodingKeys: String, CodingKey { case active, roles, recommended }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(active, forKey: .active)
        try c.encodeIfPresent(roles, forKey: .roles)
        try c.encodeIfPresent(recommended, forKey: .recommended)
    }
}

public extension APIClient {
    func roleRules() async throws -> RoleRulesEnvelope {
        try await request(.get, "/role-rules")
    }

    func updateRoleRule(id: String, _ patch: RoleRulePatch) async throws -> RoleRule {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await request(.patch, "/role-rules/\(encoded)", body: patch)
    }
}
