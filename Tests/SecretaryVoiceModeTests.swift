import XCTest
@testable import TaskFlow

final class SecretaryVoiceModeTests: XCTestCase {
    func testDefaultPreservesOldRequest() {
        XCTAssertEqual(SecretaryVoiceMode.standard.requestFields(voice: "Puck", chatID: "chat-1"),
                       ["voice": "Puck", "chat_id": "chat-1"])
    }
    func testExperimentalModesAreExplicit() {
        for mode in [SecretaryVoiceMode.pipecatLive, .pipecatChat] {
            XCTAssertEqual(mode.requestFields(voice: "Kore", chatID: "c")["mode"], mode.rawValue)
        }
    }
    func testUnknownStoredModeFallsBackToCurrentStack() {
        XCTAssertEqual(SecretaryVoiceMode.fromStoredValue("unknown"), .standard)
        XCTAssertEqual(SecretaryVoiceMode.fromStoredValue(nil), .standard)
    }
    func testOnlyChatExperimentDisablesScreen() {
        XCTAssertTrue(SecretaryVoiceMode.standard.supportsScreen)
        XCTAssertTrue(SecretaryVoiceMode.pipecatLive.supportsScreen)
        XCTAssertFalse(SecretaryVoiceMode.pipecatChat.supportsScreen)
    }
}
