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

        /// Состояние починки; цвет строки задаёт экран (владелец 12.10.2026):
        /// никого нет — красный, работают — зелёный, сдано и ждёт — синий,
        /// исполнитель упёрся в блок — оранжевый.
        enum Phase { case fixed, blocked, waiting, working, idle }

        var phase: Phase {
            if fixed { return .fixed }
            if state == "blocked" { return .blocked }
            if state == "review" { return .waiting }
            if assignee_name != nil || state == "in_progress" { return .working }
            return .idle
        }

        var statusLine: String {
            switch phase {
            case .fixed: "Починено"
            case .blocked: "Исполнитель не справился · заблокировано"
            case .waiting: "Исполнитель сдал починку · ждёт приёмки"
            case .working: "Не починено · в работе" + (assignee_name.map { ": \($0)" } ?? "")
            case .idle: "Не починено · ждёт исполнителя"
            }
        }

        /// «Время работы: 7 мин · Архитектор» — кто работал, в той же строке.
        var workLine: String? {
            guard work_seconds > 0 else { return nil }
            let names = workers.map(\.name).joined(separator: ", ")
            return "Время работы: \(SystemState.duration(work_seconds))" + (names.isEmpty ? "" : " · \(names)")
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
