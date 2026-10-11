import XCTest
@testable import TaskFlow
final class OverviewActivityTests: XCTestCase {
    func testCalendarCountsLocalDaysAndKeepsWeekColumns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        let midnightUTC = ISO8601DateFormatter().date(from: "2026-10-10T22:30:00Z")!
        let days = CompletionCalendar.days(dates: [midnightUTC, midnightUTC], now: midnightUTC, calendar: calendar)
        XCTAssertEqual(days.count, 84)
        XCTAssertEqual(calendar.component(.weekday, from: days[0].date), 2)
        XCTAssertEqual(days.first(where: { calendar.isDate($0.date, inSameDayAs: midnightUTC) })?.count, 2)
        XCTAssertEqual(days.reduce(0) { $0 + $1.count }, 2)
    }
    func testWeeklySummaryMatchesServerPayload() throws {
        let data = Data(#"{"greeting":"Неделя","accomplishments":["Готово"],"missed_or_overdue":[],"next_week_focus":["План"],"productivity_score":72,"stats":{"completed_count":3,"overdue_count":1,"active_count":2},"generated_at":"2026-10-11"}"#.utf8)
        let value = try JSONDecoder().decode(WeeklySummary.self, from: data)
        XCTAssertEqual(value.stats.completed_count, 3)
        XCTAssertEqual(value.next_week_focus, ["План"])
    }
}
