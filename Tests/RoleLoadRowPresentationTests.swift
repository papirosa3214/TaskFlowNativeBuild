import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class RoleLoadRowPresentationTests: XCTestCase {
    func testEmptyAndSingleLaneHaveStandardMinimumHeight() {
        XCTAssertEqual(RoleLoadRowPresentation.height(laneCount: 0, openCount: 0, collapsed: false), 104)
        XCTAssertEqual(RoleLoadRowPresentation.height(laneCount: 1, openCount: 0, collapsed: false), 104)
    }

    func testBusyRowsGrowToFitAllLanesAndOpenSlots() {
        XCTAssertEqual(RoleLoadRowPresentation.height(laneCount: 4, openCount: 2, collapsed: false), 200)
    }

    func testCollapseDiscardsChartHeightAndRetainsTouchTarget() {
        XCTAssertEqual(RoleLoadRowPresentation.height(laneCount: 10, openCount: 3, collapsed: true), 44)
        XCTAssertEqual(RoleLoadRowPresentation.height(laneCount: 0, openCount: 0, collapsed: true), 44)
    }

    func testRolesCollapseIndependentlyAndCanBeRestored() {
        var state = RoleLoadRowPresentation()
        state.toggle("analyst")
        state.toggle("builder")
        XCTAssertTrue(state.isCollapsed("analyst"))
        XCTAssertTrue(state.isCollapsed("builder"))
        state.toggle("analyst")
        XCTAssertFalse(state.isCollapsed("analyst"))
        XCTAssertTrue(state.isCollapsed("builder"))
    }
}
