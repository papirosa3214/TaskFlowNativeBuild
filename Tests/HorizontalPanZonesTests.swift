import XCTest
import UIKit
@testable import TaskFlow

final class HorizontalPanZonesTests: XCTestCase {
    @MainActor
    func testPagingRecognizerCancelsTaskTouchAndKeepsEdgeActions() {
        let frame = CGRect(x: 10, y: 100, width: 390, height: 700)
        let gesture = HorizontalPan(onChange: { _ in }, onEnd: { _, _ in }, pagingFrame: frame)
        let recognizer = gesture.makeRecognizer()
        XCTAssertTrue(recognizer.cancelsTouchesInView, "Paging must cancel the task button touch")
        XCTAssertTrue(recognizer.acceptsStart(localX: 195, globalX: 205, boundsWidth: 390, rowIsOpen: false))
        XCTAssertFalse(recognizer.acceptsStart(localX: 20, globalX: 30, boundsWidth: 390, rowIsOpen: false))
        XCTAssertFalse(recognizer.acceptsStart(localX: 370, globalX: 380, boundsWidth: 390, rowIsOpen: false))
        XCTAssertFalse(recognizer.acceptsStart(localX: 195, globalX: 205, boundsWidth: 390, rowIsOpen: true))
    }

    @MainActor
    func testPagingKeepsItsExistingDistanceAndDirectionThresholds() {
        let recognizer = HorizontalPan(onChange: { _ in }, onEnd: { _, _ in }, pagingFrame: CGRect(x: 0, y: 0, width: 390, height: 700)).makeRecognizer()
        XCTAssertFalse(recognizer.acceptsEnd(dx: 79, dy: 0))
        XCTAssertTrue(recognizer.acceptsEnd(dx: 80, dy: 0))
        XCTAssertTrue(recognizer.acceptsEnd(dx: -100, dy: 20))
        XCTAssertFalse(recognizer.acceptsEnd(dx: 100, dy: 50))
        XCTAssertFalse(recognizer.acceptsEnd(dx: 100, dy: 80))
    }

    @MainActor
    func testRowRecognizerStillAcceptsOnlyItsConfiguredEdges() {
        let recognizer = HorizontalPan(onChange: { _ in }, onEnd: { _, _ in }, onlyEdgeInset: 32).makeRecognizer()
        XCTAssertTrue(recognizer.acceptsStart(localX: 20, globalX: 30, boundsWidth: 390, rowIsOpen: false))
        XCTAssertFalse(recognizer.acceptsStart(localX: 195, globalX: 205, boundsWidth: 390, rowIsOpen: false))
        XCTAssertTrue(recognizer.acceptsStart(localX: 370, globalX: 380, boundsWidth: 390, rowIsOpen: false))
    }

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
