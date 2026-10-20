import XCTest
@testable import TaskFlow

final class HorizontalPanZonesTests: XCTestCase {
    func testRowSwipeIsLimitedToEitherEdge() {
        XCTAssertTrue(HorizontalPanZones.allowsRowSwipe(startX: 24, boundsWidth: 390, edgeWidth: 32))
        XCTAssertTrue(HorizontalPanZones.allowsRowSwipe(startX: 366, boundsWidth: 390, edgeWidth: 32))
        XCTAssertFalse(HorizontalPanZones.allowsRowSwipe(startX: 40, boundsWidth: 390, edgeWidth: 32))
    }

    func testPagingSwipeIsLimitedToInterior() {
        let frame = CGRect(x: 0, y: 100, width: 390, height: 700)
        XCTAssertFalse(HorizontalPanZones.allowsPagingSwipe(startX: 24, frame: frame, edgeWidth: 32))
        XCTAssertFalse(HorizontalPanZones.allowsPagingSwipe(startX: 366, frame: frame, edgeWidth: 32))
        XCTAssertTrue(HorizontalPanZones.allowsPagingSwipe(startX: 195, frame: frame, edgeWidth: 32))
    }

    func testOpenRowBlocksPagingEverywhereUntilClosed() {
        let frame = CGRect(x: 0, y: 100, width: 390, height: 700)
        XCTAssertFalse(HorizontalPanZones.allowsPagingSwipe(
            startX: 195,
            frame: frame,
            edgeWidth: 32,
            rowIsOpen: true
        ))
    }

    func testPagingSwipeRejectsInvalidNarrowFrame() {
        XCTAssertFalse(HorizontalPanZones.allowsPagingSwipe(
            startX: 8,
            frame: CGRect(x: 0, y: 0, width: 32, height: 100),
            edgeWidth: 16
        ))
    }
}
