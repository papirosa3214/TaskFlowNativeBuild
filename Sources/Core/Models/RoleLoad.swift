import Foundation

struct RoleLoad: Decodable {
    let window: String
    let from: String
    let to: String
    let now: String
    let roles: [Role]
    let attempts: [Attempt]
    let active_now: [Active]
    let open_slots: [OpenSlot]

    struct Role: Decodable, Identifiable {
        let key: String
        let title: String
        let position: Int
        var id: String { key }
    }
    struct Attempt: Decodable, Identifiable {
        let id: String
        let task_id: String
        let task_title: String
        let subtask_id: String?
        let routing_role: String?
        let started_at: String
        let ended_at: String?
        let outcome: String?
        let active: Bool
    }
    struct Active: Decodable, Identifiable {
        let id: String
        let task_id: String
        let task_title: String
        let role_key: String?
        let started_at: String?
        let heartbeat_at: String?
    }
    struct OpenSlot: Decodable, Identifiable {
        let id: String
        let task_title: String
        let role_key: String?
        let state: String
    }
    struct Row: Identifiable {
        let id: String
        let title: String
        let attempts: [Attempt]
        let active: [Active]
        let open: [OpenSlot]
    }
    var rows: [Row] {
        var keys = roles.sorted { $0.position < $1.position }.map(\.key)
        let extra = Set(attempts.map { $0.routing_role ?? "" } + active_now.map { $0.role_key ?? "" } + open_slots.map { $0.role_key ?? "" })
        keys += extra.subtracting(keys).sorted()
        return keys.map { key in
            Row(id: key, title: roles.first { $0.key == key }?.title ?? (key.isEmpty ? "Без роли" : key),
                attempts: attempts.filter { ($0.routing_role ?? "") == key },
                active: active_now.filter { ($0.role_key ?? "") == key },
                open: open_slots.filter { ($0.role_key ?? "") == key })
        }
    }
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    func fraction(_ value: String) -> Double {
        guard let start = Self.date(from), let end = Self.date(to), let date = Self.date(value), end > start else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
}
