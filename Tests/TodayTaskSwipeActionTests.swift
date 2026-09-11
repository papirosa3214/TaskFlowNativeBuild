import XCTest
@testable import TaskFlow

final class TodayTaskSwipeActionTests: XCTestCase {
    func testReviewTaskGetsAcceptActionForOwner() {
        let task = TestTaskFactory.makeTask(id: "review", agentState: .review)
        XCTAssertEqual(TodayTaskSwipeAction.action(for: task, isOwner: true), .acceptReview)
    }

    func testUnconfirmedTaskGetsReadyActionForOwner() {
        let task = TestTaskFactory.makeTask(id: "unconfirmed", assigneeId: "agent-1")
        XCTAssertEqual(TodayTaskSwipeAction.action(for: task, isOwner: true), .markReadyForPickup)
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
