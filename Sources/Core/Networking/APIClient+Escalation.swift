import Foundation

/// Шаг напоминания о просрочке: через сколько часов после срока, для каких
/// приоритетов (1 — самый срочный, шаг действует на задачах с приоритетом
/// до `priorityMax` включительно) и куда слать. Сервер — `/api/escalation/*`.
struct EscalationStep: Codable, Hashable, Sendable {
    var afterHours: Int
    var priorityMax: Int
    var channels: [String]
    enum CodingKeys: String, CodingKey {
        case afterHours = "after_hours", priorityMax = "priority_max", channels
    }
    var sendsPush: Bool { channels.contains("apns") }
}

struct EscalationRule: Codable, Sendable, Equatable {
    var enabled: Bool
    var quietFrom: String
    var quietTo: String
    var weekdays: [Int]
    var steps: [EscalationStep]
    enum CodingKeys: String, CodingKey {
        case enabled, weekdays, steps
        case quietFrom = "quiet_from", quietTo = "quiet_to"
    }
}

struct EscalationSaveResult: Decodable, Sendable {
    let warning: String?
}

struct EscalationPreview: Decodable, Sendable {
    let days: Int
    let count: Int
}

struct EscalationEvent: Decodable, Identifiable, Sendable {
    let id: String
    let taskTitle: String?
    let sentAt: String
    enum CodingKeys: String, CodingKey {
        case id
        case taskTitle = "task_title", sentAt = "sent_at"
    }
}

extension APIClient {
    func escalationRule() async throws -> EscalationRule {
        try await request(.get, "/escalation/rules")
    }
    func saveEscalationRule(_ rule: EscalationRule) async throws -> EscalationSaveResult {
        try await request(.put, "/escalation/rules", body: rule)
    }
    func escalationPreview(days: Int = 7) async throws -> EscalationPreview {
        try await request(.get, "/escalation/preview", query: [URLQueryItem(name: "days", value: String(days))])
    }
    func escalationRecent(days: Int = 7) async throws -> [EscalationEvent] {
        struct Envelope: Decodable { let events: [EscalationEvent] }
        let result: Envelope = try await request(.get, "/escalation/recent", query: [URLQueryItem(name: "days", value: String(days))])
        return result.events
    }
}
