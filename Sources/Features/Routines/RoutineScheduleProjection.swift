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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: runAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: runAt)
    }

    func day(in timezone: TimeZone = .current) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var timeLabel: String {
        guard let date else { return runAt }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: timezone)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

enum RoutineScheduleProjection {
    /// Keep one entry per automation + instant, preferring a real execution.
    static func visible(_ occurrences: [RoutineOccurrence], projects: Set<String>?) -> [RoutineOccurrence] {
        var byInstant: [String: RoutineOccurrence] = [:]
        for occurrence in occurrences {
            guard let date = occurrence.date else { continue }
            if let projects, let project = occurrence.projectId, !projects.contains(project) { continue }
            let key = "\(occurrence.scheduleId)@\(date.timeIntervalSince1970)"
            if let existing = byInstant[key], existing.status != "scheduled", occurrence.status == "scheduled" { continue }
            byInstant[key] = occurrence
        }
        return byInstant.values.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date! < $1.date!
        }
    }
}
