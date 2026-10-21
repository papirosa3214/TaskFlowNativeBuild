import XCTest
@testable import TaskFlow

final class TaskNumberTests: XCTestCase {
    /// МСК: 12 октября 2026, 13:10 → «МАК-1210-1310».
    func testNumberIsDayMonthHourMinuteInMoscow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 13, minute: 10))!
        XCTAssertEqual(TaskNumber.text(for: date), "МАК-1210-1310")
    }

    /// `created_at` приходит с сервера в UTC — в номере должна быть МСК.
    func testNumberFromServerCreatedAtIsConvertedToMoscow() throws {
        XCTAssertEqual(TaskNumber.text(forCreatedAt: "2026-10-12 10:10:00"), "МАК-1210-1310")
    }

    func testNumberPadsSingleDigits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4))!
        XCTAssertEqual(TaskNumber.text(for: date), "МАК-0201-0304")
    }

    func testNumberIsNilWithoutDate() {
        XCTAssertNil(TaskNumber.text(for: nil))
        XCTAssertNil(TaskNumber.text(forCreatedAt: nil))
    }
}
