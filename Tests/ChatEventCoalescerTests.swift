import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class ChatEventCoalescerTests: XCTestCase {
    /// Сброс планируется один раз на окно, события выходят все и по порядку.
    @objc func testOneFlushPerWindowKeepsOrder() {
        var batch = ChatEventCoalescer<Int>()
        XCTAssertTrue(batch.enqueue(1))
        XCTAssertFalse(batch.enqueue(2))
        XCTAssertFalse(batch.enqueue(3))
        XCTAssertEqual(batch.drain(), [1, 2, 3])
        XCTAssertEqual(batch.drain(), [])
        XCTAssertTrue(batch.enqueue(4))
    }

    @objc func testWindowIsShortEnoughToFeelInstant() {
        XCTAssertLessThanOrEqual(ChatEventCoalescer<Int>.window, .milliseconds(120))
        XCTAssertGreaterThanOrEqual(ChatEventCoalescer<Int>.window, .milliseconds(30))
    }
}
