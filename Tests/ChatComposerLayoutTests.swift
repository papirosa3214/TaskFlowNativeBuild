import Foundation
import XCTest
@testable import TaskFlow

/// Два состояния панели ввода и правило каретки
/// (LOCK-CHAT-COMPOSER-TWO-STATES-20261029).
final class ChatComposerLayoutTests: XCTestCase {
    func testNewPanelIsCompactUntilExpanded() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, hasExpanded: false), .compact)
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, hasExpanded: true), .full)
    }

    func testNativePanelIsAlwaysFull() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .standard, hasExpanded: false), .full)
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .standard, hasExpanded: true), .full)
    }

    func testMicrophoneDoesNotFocusField() {
        // Клавиатура на микрофон не выходит (владелец 29.10.2026).
        XCTAssertFalse(ChatComposerLayoutPolicy.focusesField(.microphonePressed))
    }

    func testTranscriptionDoesNotFocusField() {
        XCTAssertFalse(ChatComposerLayoutPolicy.focusesField(.transcriptionInserted))
    }

    func testMentionDoesFocusField() {
        XCTAssertTrue(ChatComposerLayoutPolicy.focusesField(.mentionInserted))
    }
}
