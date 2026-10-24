import Foundation

/// An occurrence is a calendar entry, never a task. Only the server creates tasks.
struct RoutineOccurrence: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let scheduleId: String
    let title: String
    let timezone: String
    let projectId: String?
    let runAt: String
    let taskId: String?
    let status: String
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case id, title, timezone, status, detail
        case scheduleId = "schedule_id", projectId = "project_id"
        case runAt = "run_at", taskId = "task_id"
    }

    var date: Date? {
        // Общий разборщик ISO8601 из Core: свой `ISO8601DateFormatter`
        // создавался на каждый вызов, а `date` читается и в ключе, и в
        // компараторе сортировки — по несколько раз на вхождение.
        DateFormats.iso8601(runAt)
    }

    func day(in timezone: TimeZone = .current) -> String? {
        guard let date else { return nil }
        return CalendarDateMath.dateString(date, timeZone: timezone)
    }

    var timeLabel: String {
        guard let date else { return runAt }
        return Self.timeFormatter(for: timezone).string(from: date)
    }

    /// Форматтер «ЧЧ:ММ» на таймзону рутины — создаётся один раз на таймзону,
    /// а не на каждую подпись.
    private static let timeFormatters = NSCache<NSString, DateFormatter>()

    private static func timeFormatter(for timezone: String) -> DateFormatter {
        if let cached = timeFormatters.object(forKey: timezone as NSString) { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: timezone)
        formatter.dateFormat = "HH:mm"
        timeFormatters.setObject(formatter, forKey: timezone as NSString)
        return formatter
    }
}

enum RoutineScheduleProjection {
    /// Keep one entry per automation + instant, preferring a real execution.
    static func visible(_ occurrences: [RoutineOccurrence], projects: Set<String>?) -> [RoutineOccurrence] {
        // Дату разбираем ОДИН раз на вхождение и сортируем по готовым `Date`:
        // раньше компаратор звал `$0.date`/`$1.date` на каждом сравнении, то
        // есть разбор даты шёл по O(n log n) раз за сортировку.
        var byInstant: [String: (occurrence: RoutineOccurrence, date: Date)] = [:]
        for occurrence in occurrences {
            guard let date = occurrence.date else { continue }
            if let projects, let project = occurrence.projectId, !projects.contains(project) { continue }
            let key = "\(occurrence.scheduleId)@\(date.timeIntervalSince1970)"
            if let existing = byInstant[key], existing.occurrence.status != "scheduled", occurrence.status == "scheduled" { continue }
            byInstant[key] = (occurrence, date)
        }
        return byInstant.values
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.occurrence.id < rhs.occurrence.id }
                return lhs.date < rhs.date
            }
            .map(\.occurrence)
    }
}
