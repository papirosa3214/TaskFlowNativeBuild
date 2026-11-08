import XCTest
@testable import TaskFlow

/// Свайпы строки задачи в «Проектах». Проверки перенесены из удалённого
/// `TodayTaskSwipeActionTests` (06.11.2026, вместе с разделом «Сегодня»):
/// там они стояли рядом с правилами строки «Сегодня».
///
/// Владелец 08.11.2026: «у меня полномочия не ограничены» — флаг готовности
/// и исполнитель регулируют роли и сервер, а не его свайпы. Поэтому «Принять»
/// показывается на ЛЮБОЙ живой задаче, в каком бы состоянии она ни была.
final class ProjectTaskSwipeActionTests: XCTestCase {
    func testUnconfirmedTaskGetsCompleteSwipeForOwner() {
        let task = TestTaskFactory.makeTask(id: "unconfirmed", assigneeId: "agent-1")
        XCTAssertEqual(ProjectTaskSwipeAction.action(for: task, isOwner: true), .complete)
    }

    /// Сданная на приёмку задача (двойная галочка критика) с опущенным флагом
    /// готовности: раньше свайпа не было вообще — только «В архив».
    func testReviewTaskGetsCompleteSwipeWithoutReadyFlag() {
        let task = TestTaskFactory.makeTask(id: "reviewed", assigneeId: "role_critic", agentState: .review)
        XCTAssertEqual(
            ProjectTaskSwipeAction.action(for: task, isOwner: true, currentUserID: "u-owner"),
            .complete
        )
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

    func testNonOwnerHasNoSwipe() {
        let task = TestTaskFactory.makeTask(id: "someone", assigneeId: "agent-1")
        XCTAssertNil(ProjectTaskSwipeAction.action(for: task, isOwner: false))
    }
}
