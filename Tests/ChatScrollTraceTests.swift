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
        for tick in 10000..<120000 {
            trace.append(geometry, rowIDs: ["a"], liveTurnCount: 1, nearBottom: false, positionedByUser: true, at: Double(tick) * 0.01)
        }
        XCTAssertEqual(trace.entries.count, ChatScrollTraceBuffer.capacity)
    }

    @objc func testSeparatesRowReplacementFromGeometryChange() {
        var trace = ChatScrollTraceBuffer()
        let geometry = ChatScrollGeometry(offsetY: 0, contentHeight: 2000, viewportHeight: 800, visibleMaxY: 800)
        trace.append(geometry, rowIDs: ["a", "b"], liveTurnCount: 1, nearBottom: false, positionedByUser: false, at: 0)
        trace.append(geometry, rowIDs: ["a", "b"], liveTurnCount: 1, nearBottom: false, positionedByUser: false, at: 1)
        trace.append(geometry, rowIDs: ["a", "c"], liveTurnCount: 1, nearBottom: false, positionedByUser: false, at: 2)
        XCTAssertEqual(trace.entries.map(\.rowsChanged), [true, false, true])
    }

    /// События (клавиатура, отправка, фаза прокрутки) пишутся сразу, без
    /// прореживания: по ним видно, ЧТО случилось перед скачком.
    @objc func testEventsBypassSamplingAndCarryContext() {
        var trace = ChatScrollTraceBuffer()
        let geometry = ChatScrollGeometry(offsetY: 0, contentHeight: 2000, viewportHeight: 800, visibleMaxY: 800)
        let context = ChatScrollContext(keyboardHeight: 336, composerFocused: true, phase: "idle")
        trace.append(geometry, rowIDs: ["a"], liveTurnCount: 0, nearBottom: true, positionedByUser: false,
                     context: context, at: 0)
        XCTAssertTrue(trace.appendEvent("keyboard", geometry: geometry, context: context, at: 0.01))
        XCTAssertTrue(trace.appendEvent("send", geometry: geometry, context: context, at: 0.02))
        XCTAssertEqual(trace.entries.map(\.event), [nil, "keyboard", "send"])
        XCTAssertEqual(trace.entries.last?.context.keyboardHeight, 336)
        XCTAssertEqual(trace.entries.last?.context.composerFocused, true)
        XCTAssertGreaterThan(trace.entries.last?.wallTime ?? 0, 1_700_000_000)
    }

    /// Хранятся последние сеансы, старые удаляются; имена сортируются по времени.
    @objc func testKeepsOnlyRecentSessionFiles() {
        let names = (1...45).map { String(format: "session-20261027-%06d.json", $0) } + ["latest.json", "notes.txt"]
        let doomed = ChatScrollTraceFiles.filesToDelete(names.shuffled(), keep: 40)
        XCTAssertEqual(doomed.count, 6)
        XCTAssertTrue(doomed.contains("latest.json"))
        XCTAssertTrue(doomed.contains("session-20261027-000001.json"))
        XCTAssertFalse(doomed.contains("session-20261027-000045.json"))
        XCTAssertFalse(doomed.contains("notes.txt"))
    }
}
