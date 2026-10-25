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
    /// Ходы ролей в чате без карточки. Сервер отдаёт их отдельно: в
    /// `attempts` их нет (там `task_id` обязателен), но по времени работы
    /// это такая же нагрузка роли.
    let chat_turns: [ChatTurn]?

    /// Ход роли в чате: интервал работы и название работы — из отчёта роли.
    struct ChatTurn: Decodable, Identifiable {
        let id: String
        let chat_id: String
        let chat_title: String?
        let role_id: String
        let role_key: String?
        let started_at: String
        let ended_at: String
        /// Название работы: из отчёта роли по этому ходу.
        let title: String
    }

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
        /// Момент создания задачи — из него считается номер «МАК-ДДММ-ЧЧММ».
        let task_created_at: String?
        let subtask_id: String?
        let routing_role: String?
        let started_at: String
        let ended_at: String?
        let outcome: String?
        let active: Bool
        /// Служебная карточка починки поломки («Состояние системы»).
        let service: Bool?
    }
    struct Active: Decodable, Identifiable {
        let id: String
        let task_id: String
        let task_title: String
        /// Момент создания задачи — из него считается номер «МАК-ДДММ-ЧЧММ».
        let task_created_at: String?
        let role_key: String?
        let started_at: String?
        let heartbeat_at: String?
    }
    struct OpenSlot: Decodable, Identifiable, Equatable {
        let id: String
        let task_title: String
        /// Момент создания задачи — из него считается номер «МАК-ДДММ-ЧЧММ».
        let task_created_at: String?
        let role_key: String?
        let state: String
    }
    struct Row: Identifiable {
        let id: String
        let title: String
        let attempts: [Attempt]
        let active: [Active]
        let open: [OpenSlot]
        let chat: [ChatTurn]
    }
    /// Идёт ли по карточке починка поломки: у «идёт сейчас» своего признака
    /// нет, берём его у интервалов той же карточки.
    func isService(taskID: String) -> Bool {
        attempts.contains { $0.service == true && $0.task_id == taskID }
    }
    var rows: [Row] {
        var keys = roles.sorted { $0.position < $1.position }.map(\.key)
        let extra = Set(attempts.map { $0.routing_role ?? "" } + active_now.map { $0.role_key ?? "" } + open_slots.map { $0.role_key ?? "" } + (chat_turns ?? []).map { $0.role_key ?? "" })
        keys += extra.subtracting(keys).sorted()
        return keys.map { key in
            Row(id: key, title: roles.first { $0.key == key }?.title ?? (key.isEmpty ? "Без роли" : key),
                attempts: attempts.filter { ($0.routing_role ?? "") == key },
                active: active_now.filter { ($0.role_key ?? "") == key },
                open: open_slots.filter { ($0.role_key ?? "") == key },
                chat: (chat_turns ?? []).filter { ($0.role_key ?? "") == key })
        }
    }
    static func date(_ value: String) -> Date? {
        // Разбор ISO8601 с миллисекундами и без них — общий кэшированный
        // разборщик из Core: создавать `ISO8601DateFormatter` на каждый вызов
        // дорого, а даты зовутся сотнями за проход списка.
        DateFormats.iso8601(value)
    }
    func fraction(_ value: String) -> Double {
        guard let start = Self.date(from), let end = Self.date(to), let date = Self.date(value), end > start else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
}
