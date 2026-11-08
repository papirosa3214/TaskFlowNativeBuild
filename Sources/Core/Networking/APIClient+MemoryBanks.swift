import Foundation

/// Память TaskFlow глазами владельца (08.11.2026): кто в неё обращается и что
/// в ней лежит.
///
/// Память одна — Mnemosyne. Банки (`tf-team`, `tf-role-<роль>`) держат
/// приватность: роль видит свою и командную, владелец — всё.
public struct MemoryAgentStat: Decodable, Identifiable, Sendable {
    public let roleKey: String?
    public let name: String
    /// Обращений, записанных в журнал (с 08.11.2026).
    public let calls: Int
    /// Из них за последнюю неделю.
    public let callsWeek: Int
    public let lastAt: String?
    /// Сколько записей помнит этот агент.
    public let records: Int
    /// Сколько раз записи читали — счётчик самой памяти, старше журнала.
    public let uses: Int

    public var id: String { roleKey ?? "owner" }

    public enum CodingKeys: String, CodingKey {
        case roleKey = "role_key"
        case name, calls
        case callsWeek = "calls_week"
        case lastAt = "last_at"
        case records, uses
    }

    /// «80 записей · 214 прочтений» — что видно без раскрытия.
    public var subtitle: String {
        var parts = ["\(records) \(Self.plural(records, "запись", "записи", "записей"))"]
        if uses > 0 {
            parts.append("\(uses) \(Self.plural(uses, "прочтение", "прочтения", "прочтений"))")
        }
        return parts.joined(separator: " · ")
    }

    /// «12 обращений · сегодня 19:15» — правая сторона строки.
    public var callsText: String {
        guard calls > 0 else { return "не спрашивал" }
        return "\(calls) \(Self.plural(calls, "обращение", "обращения", "обращений"))"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = n % 100
        let mod10 = n % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        if mod10 == 1 { return one }
        if mod10 >= 2 && mod10 <= 4 { return few }
        return many
    }
}

public struct MemoryAgentsEnvelope: Decodable, Sendable {
    public let agents: [MemoryAgentStat]
    public let banks: [String]
}

public struct MemoryBrowseItem: Decodable, Identifiable, Sendable {
    public let id: String
    public let bank: String
    public let roleKey: String?
    public let text: String
    public let importance: Double?
    public let at: String?

    public enum CodingKeys: String, CodingKey {
        case id, bank
        case roleKey = "role_key"
        case text, importance, at
    }

    /// «Командная» для `tf-team`, имя роли для `tf-role-*` — так владелец
    /// видит, чья это память, не зная внутренних имён банков.
    public var bankTitle: String {
        if bank == "tf-team" { return "Командная память" }
        if bank.hasPrefix("tf-role-") { return "Роль: " + bank.replacingOccurrences(of: "tf-role-", with: "") }
        return bank
    }
}

public struct MemoryBrowseEnvelope: Decodable, Sendable {
    public let items: [MemoryBrowseItem]
    public let banks: [String]
}

public extension APIClient {
    /// Кто обращался к памяти и сколько записей держит.
    func memoryAgents() async throws -> MemoryAgentsEnvelope {
        try await request(.get, "/memory/agents")
    }

    /// Что лежит в банках. Пустой запрос — свежее сверху.
    func memoryBrowse(query: String = "", limit: Int = 20) async throws -> MemoryBrowseEnvelope {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if !query.isEmpty {
            items.insert(URLQueryItem(name: "q", value: query), at: 0)
        }
        return try await request(.get, "/memory/browse", query: items)
    }
}
