import Foundation

/// Архив и статистика закрытых задач на телефоне (владелец 13.11.2026):
/// «мне сама задача со всем содержимым не нужна, но хотя бы карточка с
/// итогом и названием… архив 1 мес, можно удалять с телефона, но не из
/// статистики и тем более из базы сервера… статистика — фото с сервера,
/// чисто по дням, в какой день сколько задач».
///
/// Здесь только данные и слияние дельт — без сети и UI, проверяется тестом
/// на хосте (`Tools/test_closed_tasks_feed.py`).

/// Мини-карточка закрытой задачи (`GET /api/tasks/closed`).
struct ClosedTaskItem: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case completed, archived }

    let id: String
    var title: String
    var projectName: String?
    var kind: Kind
    /// Когда закрыта — UTC «YYYY-MM-DD HH:MM:SS», как отдаёт сервер.
    var closedAt: String
    /// Итог одной строкой.
    var outcome: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, outcome
        case projectName = "project_name"
        case closedAt = "closed_at"
    }
}

struct ClosedTasksResponse: Decodable, Equatable, Sendable {
    let serverTime: String
    let full: Bool
    let items: [ClosedTaskItem]
    let removedIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case full, items
        case serverTime = "server_time"
        case removedIDs = "removed_ids"
    }
}

/// Сколько задач выполнено в день (`GET /api/stats/completed-daily`).
struct DailyCount: Codable, Equatable, Sendable {
    let day: String
    let count: Int
}

struct DailyStatsResponse: Decodable, Equatable, Sendable {
    let serverTime: String
    let full: Bool
    let days: [DailyCount]

    private enum CodingKeys: String, CodingKey {
        case full, days
        case serverTime = "server_time"
    }
}

/// То, что телефон держит у себя: мини-карточки за месяц, убранные с
/// телефона id, снимок статистики и курсоры обеих дельт.
struct ClosedTasksSnapshot: Codable, Equatable, Sendable {
    /// Сколько дней мини-карточки живут на телефоне.
    static let windowDays = 30

    private(set) var items: [ClosedTaskItem] = []
    private(set) var hiddenIDs: Set<String> = []
    private(set) var closedCursor: String?
    /// День «YYYY-MM-DD» → сколько задач выполнено.
    private(set) var days: [String: Int] = [:]
    private(set) var statsCursor: String?

    /// Дельта мини-карточек: полный ответ заменяет всё, частичный — правит
    /// пришедшие и убирает удалённые. Старше месяца и убранное с телефона
    /// не хранится.
    mutating func apply(_ response: ClosedTasksResponse, now: Date = Date()) {
        var byID: [String: ClosedTaskItem] = response.full
            ? [:]
            : Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for id in response.removedIDs { byID[id] = nil }
        for item in response.items where !hiddenIDs.contains(item.id) { byID[item.id] = item }
        items = Array(byID.values)
        closedCursor = response.serverTime
        prune(now: now)
    }

    /// Снимок статистики: полный заменяет, частичный правит только пришедшие дни.
    mutating func apply(_ response: DailyStatsResponse) {
        if response.full { days = [:] }
        for entry in response.days {
            days[entry.day] = entry.count > 0 ? entry.count : nil
        }
        statsCursor = response.serverTime
    }

    /// «Убрать с телефона»: из архива телефона, не из статистики и не с сервера.
    mutating func hide(_ id: String) {
        hiddenIDs.insert(id)
        items.removeAll { $0.id == id }
    }

    /// Восстановленная задача уходит из архива сразу, не дожидаясь дельты.
    mutating func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// Старше месяца — с телефона; свежие сверху.
    mutating func prune(now: Date = Date()) {
        let border = now.addingTimeInterval(-Double(Self.windowDays) * 86_400)
        items = items
            .filter { (Self.date($0.closedAt) ?? now) >= border }
            .sorted { $0.closedAt != $1.closedAt ? $0.closedAt > $1.closedAt : $0.id < $1.id }
    }

    static func date(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
