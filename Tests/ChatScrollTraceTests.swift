import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class ChatScrollTraceTests: XCTestCase {
    @objc func testCapturesBlankViewportWithoutMessageText() throws {
        var trace = ChatScrollTraceBuffer()
        let geometry = ChatScrollGeometry(offsetY: 9000, contentHeight: 2000, viewportHeight: 800, visibleMaxY: 9800)
        XCTAssertTrue(trace.append(geometry, rowIDs: ["a", "b", "b"], liveTurnCount: 1, nearBottom: true, positionedByUser: false, at: 0))
        XCTAssertEqual(trace.entries.first?.duplicateRowCount, 1)
        XCTAssertEqual(trace.entries.first?.rowCount, 3)
        XCTAssertEqual(trace.entries.first?.geometry.offsetY, 9000)
        let json = String(decoding: try JSONEncoder().encode(trace.entries), as: UTF8.self)
        XCTAssertFalse(json.contains("\"a\""))
        XCTAssertFalse(json.contains("\"b\""))
    }

    @objc func testSamplingAndCapacityAreBounded() {
        var trace = ChatScrollTraceBuffer()
        let geometry = ChatScrollGeometry(offsetY: 0, contentHeight: 2000, viewportHeight: 800, visibleMaxY: 800)
        for tick in 0..<10000 {
            trace.append(geometry, rowIDs: ["a"], liveTurnCount: 1, nearBottom: false, positionedByUser: true, at: Double(tick) * 0.01)
        }
        XCTAssertLessThanOrEqual(trace.entries.count, 1001)
        XCTAssertGreaterThan(trace.entries.count, 800)
        for tick in 10000..<40000 {
            trace.append(geometry, rowIDs: ["a"], liveTurnCount: 1, nearBottom: false, positionedByUser: true, at: Double(tick) * 0.01)
        }
        XCTAssertEqual(trace.entries.count, 1200)
    }

    @objc func testSeparatesRowReplacementFromGeometryChange() {
        var trace = ChatScrollTraceBuffer()
        let geometry = ChatScrollGeometry(offsetY: 0, contentHeight: 2000, viewportHeight: 800, visibleMaxY: 800)
        trace.append(geometry, rowIDs: ["a", "b"], liveTurnCount: 1, nearBottom: false, positionedByUser: false, at: 0)
        trace.append(geometry, rowIDs: ["a", "b"], liveTurnCount: 1, nearBottom: false, positionedByUser: false, at: 1)
        trace.append(geometry, rowIDs: ["a", "c"], liveTurnCount: 1, nearBottom: false, positionedByUser: false, at: 2)
        XCTAssertEqual(trace.entries.map(\.rowsChanged), [true, false, true])
    }
}
