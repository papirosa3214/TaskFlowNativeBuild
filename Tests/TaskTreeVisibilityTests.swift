import XCTest
@testable import TaskFlow

/// Правило «какая задача показывается корнем списка»: корнем идёт задача без
/// родителя И задача, чьего родителя нет в живом наборе. Второе — не мелочь:
/// дочерняя задача с закрытым или архивным родителем не имеет ряда, под
/// которым её можно раскрыть, и раньше пропадала из всех списков целиком
/// (владелец 08.11.2026: «чтобы я видел все задачи»).
final class TaskTreeVisibilityTests: XCTestCase {
    func testTaskWithoutParentIsRoot() {
        let ids = TaskTreeVisibility.visibleRootIDs([
            ("a", nil),
            ("b", "a"),
        ])
        XCTAssertEqual(ids, ["a"])
    }

    func testChildWithMissingParentIsRoot() {
        let ids = TaskTreeVisibility.visibleRootIDs([
            ("a", nil),
            ("orphan", "gone"),
        ])
        XCTAssertEqual(ids, ["a", "orphan"])
    }

    func testChainWithClosedMiddleStaysVisible() {
        // Середина цепочки закрыта и в набор не попала: внук поднимается в
        // корни, а не исчезает вместе с закрытым родителем.
        let ids = TaskTreeVisibility.visibleRootIDs([
            ("root", nil),
            ("grandchild", "closed-parent"),
        ])
        XCTAssertEqual(ids, ["root", "grandchild"])
    }

    func testEmptySetGivesEmptyRoots() {
        XCTAssertTrue(TaskTreeVisibility.visibleRootIDs([]).isEmpty)
    }
}
