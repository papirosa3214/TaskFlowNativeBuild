import XCTest
@testable import TaskFlow

final class PlannerBackdropVisibilityTests: XCTestCase {
    func testOnlySuccessfullyLoadedEmptyTabShowsBackdrop() {
        XCTAssertTrue(PlannerBackdropVisibility.isVisible(isLoading: false, hasError: false, visibleTaskCount: 0))
        XCTAssertFalse(PlannerBackdropVisibility.isVisible(isLoading: true, hasError: false, visibleTaskCount: 0))
        XCTAssertFalse(PlannerBackdropVisibility.isVisible(isLoading: false, hasError: true, visibleTaskCount: 0))
        XCTAssertFalse(PlannerBackdropVisibility.isVisible(isLoading: false, hasError: false, visibleTaskCount: 1))
    }
}
