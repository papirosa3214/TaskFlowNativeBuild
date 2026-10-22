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
    func testLegacyRoomsDefaultToChatButTaskTopicsKeepCardLifecycle() {
        XCTAssertEqual(ChatExecutionMode.resolve(stored: nil, taskID: nil, parentChatID: nil), .chat)
        XCTAssertEqual(ChatExecutionMode.resolve(stored: nil, taskID: "task", parentChatID: nil), .chat)
        XCTAssertEqual(ChatExecutionMode.resolve(stored: nil, taskID: "task", parentChatID: "project"), .card)
        XCTAssertEqual(ChatExecutionMode.resolve(stored: .chat, taskID: "task", parentChatID: "project"), .chat)
    }
}
