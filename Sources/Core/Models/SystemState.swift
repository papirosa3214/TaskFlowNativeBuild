import Foundation

/// `GET /api/system-state` — сводка «Состояние системы»: поломки за день и
/// все ещё не починенные, кто над ними работал и сколько времени.
struct SystemState: Decodable, Sendable {
    let counts: Counts
    let incidents: [Incident]
    let workers: [Worker]

    struct Counts: Decodable, Sendable {
        let total: Int
        let open: Int
        let fixed: Int
        let in_work: Int
    }
    struct Worker: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let name: String
        let seconds: Int
    }
    struct Incident: Decodable, Sendable, Identifiable {
        let id: String
        let key: String
        let title: String
        let fixed: Bool
        let state: String?
        let assignee_name: String?
        let work_seconds: Int
        let workers: [Worker]

        var statusLine: String {
            if fixed { return "Починено" }
            // Исполнитель сдал работу, карточка ждёт приёмки — это уже не «ждёт исполнителя».
            if state == "review" { return "Исполнитель сдал починку · ждёт приёмки" }
            let names = workers.map(\.name)
            if let who = assignee_name ?? names.first { return "Не починено · в работе: \(who)" }
            return "Не починено · ждёт исполнителя"
        }
    }

    /// «1 ч 05 мин», «12 мин», «меньше минуты».
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 1 { return seconds > 0 ? "меньше минуты" : "—" }
        if minutes < 60 { return "\(minutes) мин" }
        return "\(minutes / 60) ч \(String(format: "%02d", minutes % 60)) мин"
    }
}
