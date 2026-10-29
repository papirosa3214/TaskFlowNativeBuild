import Foundation
import XCTest
@testable import TaskFlow

final class PlanReturnGeometryTests: XCTestCase {
    func testVerticalReturnUsesSideOfBothCirclesAndHorizontalArrow() {
        for targetY in [100.0, 300.0] {
            let r = PlanReturnGeometry.route(from: CGPoint(x: 180, y: 200), to: CGPoint(x: 180, y: targetY), radius: 28, width: 360)
            XCTAssertEqual(r.start, CGPoint(x: 152, y: 200))
            XCTAssertEqual(r.end, CGPoint(x: 152, y: targetY))
            XCTAssertLessThan(r.headLeft.x, r.end.x)
            XCTAssertEqual(r.headLeft.x, r.headRight.x, accuracy: 0.001)
            XCTAssertEqual((r.headLeft.y + r.headRight.y) / 2, r.end.y, accuracy: 0.001)
        }
    }

    func testLeftEdgeUsesRightSideWithoutClipping() {
        let r = PlanReturnGeometry.route(from: CGPoint(x: 30, y: 200), to: CGPoint(x: 30, y: 100), radius: 28, width: 360)
        XCTAssertEqual(r.start, CGPoint(x: 58, y: 200))
        XCTAssertEqual(r.end, CGPoint(x: 58, y: 100))
        XCTAssertGreaterThan(r.headLeft.x, r.end.x)
    }

    func testHorizontalReturnAttachesToFacingCircleBoundaries() {
        let r = PlanReturnGeometry.route(from: CGPoint(x: 200, y: 60), to: CGPoint(x: 80, y: 60), radius: 28, width: 360)
        XCTAssertEqual(r.start, CGPoint(x: 172, y: 60))
        XCTAssertEqual(r.end, CGPoint(x: 108, y: 60))
        XCTAssertGreaterThan(r.headLeft.x, r.end.x)
    }
}
