import XCTest
@testable import TaskFlow

final class ChatMessageWithdrawalTests: XCTestCase {
    private func message(_ flag: String?) throws -> RoleChatMessage {
        let field = flag.map { ",\"can_withdraw\":\($0)" } ?? ""
        return try JSONDecoder().decode(RoleChatMessage.self, from: Data("{\"id\":\"m\",\"text\":\"Передумал\",\"is_session_marker\":false\(field)}".utf8))
    }
    func testServerAllowsWithdrawal() throws {
        XCTAssertEqual(try message("true").canWithdraw, true)
    }
    func testServerRefusesStartedMessage() throws {
        XCTAssertEqual(try message("false").canWithdraw, false)
    }
    func testOldServerDoesNotOfferUnsafeWithdrawal() throws {
        XCTAssertNil(try message(nil).canWithdraw)
    }
}
