import XCTest
@testable import TaskFlow

/// Свайпы строки задачи в «Проектах». Проверки перенесены из удалённого
/// `TodayTaskSwipeActionTests` (06.11.2026, вместе с разделом «Сегодня»):
/// там они стояли рядом с правилами строки «Сегодня».
final class ProjectTaskSwipeActionTests: XCTestCase {
    func testUnconfirmedTaskHasNoStartSwipeForOwner() {
        let task = TestTaskFactory.makeTask(id: "unconfirmed", assigneeId: "agent-1")
        XCTAssertNil(ProjectTaskSwipeAction.action(for: task, isOwner: true))
    }

    func testReadyTaskKeepsCompleteActions() throws {
        let task = try JSONDecoder().decode(ApiTask.self, from: Data(#"{"id":"ready","title":"Task","priority":1,"status":"active","pinned":0,"ready_for_pickup":1}"#.utf8))
        XCTAssertEqual(ProjectTaskSwipeAction.action(for: task, isOwner: true), .complete)
    }

    func testPersonalTaskGetsCompleteNotStart() {
        let personal = TestTaskFactory.makeTask(id: "personal", assigneeId: "u-owner")
        XCTAssertEqual(
            ProjectTaskSwipeAction.action(for: personal, isOwner: true, currentUserID: "u-owner"),
            .complete
        )
    }
}
