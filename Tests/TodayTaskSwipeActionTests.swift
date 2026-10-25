import XCTest
@testable import TaskFlow

final class TodayTaskSwipeActionTests: XCTestCase {
    func testReviewTaskGetsAcceptActionForOwner() {
        let task = TestTaskFactory.makeTask(id: "review", agentState: .review)
        XCTAssertEqual(TodayTaskSwipeAction.action(for: task, isOwner: true), .acceptReview)
    }

    func testUnconfirmedTaskHasNoStartSwipeForOwner() {
        let task = TestTaskFactory.makeTask(id: "unconfirmed", assigneeId: "agent-1")
        XCTAssertNil(TodayTaskSwipeAction.action(for: task, isOwner: true))
        XCTAssertNil(ProjectTaskSwipeAction.action(for: task, isOwner: true))
    }

    func testReadyTaskKeepsCompleteActions() throws {
        let task = try JSONDecoder().decode(ApiTask.self, from: Data(#"{"id":"ready","title":"Task","priority":1,"status":"active","pinned":0,"ready_for_pickup":1}"#.utf8))
        XCTAssertEqual(TodayTaskSwipeAction.action(for: task, isOwner: true), .complete)
        XCTAssertEqual(ProjectTaskSwipeAction.action(for: task, isOwner: true), .complete)
    }

    func testPersonalTaskGetsCompleteNotStart() {
        let personal = TestTaskFactory.makeTask(id: "personal", assigneeId: "u-owner")
        XCTAssertEqual(
            TodayTaskSwipeAction.action(for: personal, isOwner: true, currentUserID: "u-owner"),
            .complete
        )
        XCTAssertEqual(
            ProjectTaskSwipeAction.action(for: personal, isOwner: true, currentUserID: "u-owner"),
            .complete
        )
    }

    func testOtherActiveTasksKeepCompleteAndCompletedTasksHaveNoAction() throws {
        let working = TestTaskFactory.makeTask(id: "working", agentState: .inProgress)
        let completed = try JSONDecoder().decode(
            ApiTask.self,
            from: Data(#"{"id":"done","title":"Task","priority":1,"status":"completed","pinned":0,"creator_id":"u-owner"}"#.utf8)
        )

        XCTAssertEqual(TodayTaskSwipeAction.action(for: working, isOwner: true), .complete)
        XCTAssertEqual(TodayTaskSwipeAction.action(for: working, isOwner: false), .complete)
        XCTAssertNil(TodayTaskSwipeAction.action(for: completed, isOwner: true))
    }
}
