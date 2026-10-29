import Foundation
import XCTest
@testable import TaskFlow

/// Два состояния панели ввода и правило каретки
/// (LOCK-CHAT-COMPOSER-TWO-STATES-20261029).
final class ChatComposerLayoutTests: XCTestCase {
    func testNewPanelIsCompactWhileIdle() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: false, hasText: false), .compact)
    }

    func testNewPanelExpandsOnFocus() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: true, hasText: false), .full)
    }

    func testNewPanelExpandsWithText() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: false, hasText: true), .full)
    }

    func testNewPanelCollapsesBackWhenKeyboardDismissedWithoutText() {
        // Владелец 29.10.2026: «когда я сворачиваю опять клавиатуру, он
        // опять в маленький не превращается» — значит, без текста панель
        // обязана сжаться обратно.
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: false, hasText: false), .compact)
    }

    func testNativePanelIsAlwaysFull() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .standard, isFocused: false, hasText: false), .full)
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .standard, isFocused: true, hasText: false), .full)
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .standard, isFocused: false, hasText: true), .full)
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

    func testFourWorkModesInSessionWindow() {
        XCTAssertEqual(ChatSessionWorkModePolicy.allModes.count, 4)
        XCTAssertEqual(ChatSessionWorkModePolicy.allModes.map(\.title),
                       ["Работа", "Планирование", "Цель", "Исследование"])
    }

    func testResearchModeAllowedOnlyForResearcherAndSecretary() {
        XCTAssertTrue(ChatSessionWorkModePolicy.allowsResearch(roles: ["researcher"]))
        XCTAssertTrue(ChatSessionWorkModePolicy.allowsResearch(roles: ["secretary"]))
        XCTAssertFalse(ChatSessionWorkModePolicy.allowsResearch(roles: ["builder"]))
        XCTAssertFalse(ChatSessionWorkModePolicy.allowsResearch(roles: []))
    }

    func testThreeAttachmentBlocks() {
        XCTAssertEqual(ChatSessionAttachment.allCases.map(\.title), ["Фото", "Файл", "Камера"])
    }
}
