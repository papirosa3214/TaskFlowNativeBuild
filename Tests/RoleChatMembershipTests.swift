import Foundation
import XCTest
@testable import TaskFlow

final class RoleChatMembershipTests: XCTestCase {
    private func profile(account: String?, enabled: Bool = true) throws -> RoleProfile {
        let payload: [String: Any] = [
            "role": "secretary", "title": "Помощник владельца",
            "account_id": account.map { $0 as Any } ?? NSNull(),
            "status": "ready", "status_title": "Готова", "runtime_ready": true,
            "problems": [], "prompt": "", "skills": [], "tools": [],
            "fallbacks": [], "attempt_policy": [], "enabled": enabled,
        ]
        return try JSONDecoder().decode(RoleProfile.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    func testSecretaryCanBeInvitedWithNonRoleAccountID() throws {
        XCTAssertTrue(try profile(account: "u-secretary").canJoinChat)
        XCTAssertTrue(try profile(account: "role_architect").canJoinChat)
    }
    func testMissingOrDisabledAccountsCannotBeInvited() throws {
        XCTAssertFalse(try profile(account: nil).canJoinChat)
        XCTAssertFalse(try profile(account: " ").canJoinChat)
        XCTAssertFalse(try profile(account: "u-secretary", enabled: false).canJoinChat)
    }
}
