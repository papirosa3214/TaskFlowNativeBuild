import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class SecretaryVoicePresentationTests: XCTestCase {
    func testMinimizeKeepsOriginalChatAndExpandDoesNotStartAnotherCall() {
        var state = SecretaryVoicePresentation()
        XCTAssertTrue(state.begin(chatID: "original"))
        state.minimize()
        XCTAssertEqual(state.chatID, "original")
        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.begin(chatID: "another"))
        XCTAssertEqual(state.chatID, "original")
        XCTAssertTrue(state.isExpanded)
    }

    func testOnlyEndReleasesCallAndAllowsAnotherChat() {
        var state = SecretaryVoicePresentation()
        _ = state.begin(chatID: "first")
        state.minimize()
        XCTAssertTrue(state.isActive)
        state.end()
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.isExpanded)
        XCTAssertTrue(state.begin(chatID: "second"))
        XCTAssertEqual(state.chatID, "second")
    }
}
