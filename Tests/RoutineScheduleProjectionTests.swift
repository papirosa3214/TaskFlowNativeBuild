import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class RoutineScheduleProjectionTests: XCTestCase {
    private func entry(_ id: String, run: String = "2026-10-23T06:00:00.000Z", task: String? = nil, project: String? = nil) -> RoutineOccurrence {
        RoutineOccurrence(id: id, scheduleId: "english", title: "Урок английского", timezone: "Europe/Moscow", projectId: project, runAt: run, taskId: task, status: task == nil ? "scheduled" : "created", detail: nil)
    }

    func testExecutionReplacesProjectionAtSameInstant() {
        let result = RoutineScheduleProjection.visible([entry("future"), entry("real", run: "2026-10-23T06:00:00Z", task: "task-1")], projects: nil)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.taskId, "task-1")
    }

    func testProjectFilterRetainsUnassignedAutomations() {
        let result = RoutineScheduleProjection.visible([entry("one", project: "visible"), entry("two", run: "2026-10-24T06:00Z", project: "hidden"), entry("three", run: "2026-10-25T06:00:00Z")], projects: ["visible"])
        XCTAssertEqual(result.map(\.id), ["one", "three"])
    }

    func testInvalidDatesAreNotSilentlyPlacedInCalendar() {
        XCTAssertTrue(RoutineScheduleProjection.visible([entry("invalid", run: "bad")], projects: nil).isEmpty)
    }

    func testCalendarDayUsesDisplayZoneAcrossMidnight() {
        let occurrence = entry("late", run: "2026-10-23T22:00:00Z")
        XCTAssertEqual(occurrence.day(in: TimeZone(identifier: "Europe/Moscow")!), "2026-10-24")
        XCTAssertEqual(occurrence.timeLabel, "01:00")
    }
}
