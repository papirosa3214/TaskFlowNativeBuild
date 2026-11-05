import Foundation
import XCTest
@testable import TaskFlow

final class ChatExecutionModeTests: XCTestCase {
    func testWireValuesAndTitlesAreUnambiguous() throws {
        XCTAssertEqual(try JSONEncoder().encode(ChatExecutionMode.chat), Data(#""chat""#.utf8))
        XCTAssertEqual(try JSONDecoder().decode(ChatExecutionMode.self, from: Data(#""card""#.utf8)), .card)
        XCTAssertEqual(ChatExecutionMode.chat.title, "В чате")
        XCTAssertEqual(ChatExecutionMode.card.title, "По карточке")
        XCTAssertThrowsError(try JSONDecoder().decode(ChatExecutionMode.self, from: Data(#""unknown""#.utf8)))
    }
    func testModeFollowsTheTaskBindingOnly() {
        XCTAssertEqual(ChatExecutionMode.resolve(taskID: nil), .chat)
        XCTAssertEqual(ChatExecutionMode.resolve(taskID: "task"), .card)
    }
}
