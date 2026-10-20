import Foundation

/// `GET /api/system-state` — сводка «Состояние системы»: поломки за день и
/// все ещё не починенные, кто над ними работал и сколько времени.
struct SystemState: Decodable, Sendable {
    let counts: Counts
    let incidents: [Incident]
    let workers: [Worker]
    /// Закрытые (архивные) поломки: карточка починки ушла в архив — значит
    /// починка не нужна и поломка закрыта (владелец 20.10.2026). Сервер
    /// архивные поломки в `incidents` не отдаёт, поэтому клиенту нужен
    /// отдельный список: по нему он убирает из сводки строки проверок,
    /// привязанных к закрытой поломке.
    let closed: [Closed]

    /// Поломка, закрытая архивом карточки починки: id карточки и ключ
    /// поломки. Ключ (`incident_key`) нужен строке проверки, id — строке,
    /// привязанной к карточке (`diagnostic_task_ids`).
    struct Closed: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let key: String
    }

    enum CodingKeys: String, CodingKey { case counts, incidents, workers, closed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        counts = try container.decode(Counts.self, forKey: .counts)
        incidents = try container.decode([Incident].self, forKey: .incidents)
        workers = try container.decode([Worker].self, forKey: .workers)
        // Сервер без поля `closed` — не поломка: закрытых поломок просто нет.
        closed = try container.decodeIfPresent([Closed].self, forKey: .closed) ?? []
    }

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
