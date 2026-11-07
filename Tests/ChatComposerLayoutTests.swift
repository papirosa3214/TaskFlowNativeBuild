import Foundation
import XCTest
@testable import TaskFlow

/// Два состояния панели ввода и правило каретки
/// (LOCK-CHAT-COMPOSER-TWO-STATES-20261029).
final class ChatComposerLayoutTests: XCTestCase {
    func testNewPanelIsCompactWhileIdle() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: false, hasText: false), .compact)
    }

    /// Панель разворачивается по касанию поля — динамическое окно задумано
    /// так (владелец 30.10.2026). Безопасно это потому, что поле ввода одно на
    /// оба вида: проверяется отдельно, по исходнику панели.
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

    func testHiddenResearchRestoresToWork() {
        XCTAssertEqual(ChatSessionWorkModePolicy.visibleSelection(.deepResearch), .work)
        XCTAssertEqual(ChatSessionWorkModePolicy.visibleSelection(.work), .work)
        XCTAssertEqual(ChatSessionWorkModePolicy.visibleSelection(.plan), .plan)
        XCTAssertEqual(ChatSessionWorkModePolicy.visibleSelection(.goal), .goal)
    }

    func testThreeWorkModesInSessionWindow() {
        XCTAssertEqual(ChatSessionWorkModePolicy.allModes.count, 3)
        XCTAssertEqual(ChatSessionWorkModePolicy.allModes.map(\.title),
                       ["Работа", "Планирование", "Цель"])
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

    // MARK: - Каретка при смене раскладки

    /// Панель развернулась, а фокус в новом поле ещё не встал: раскладку
    /// держим, иначе панель мигает и каретка теряется (владелец 29.10.2026).
    /// Панель разворачивается и от текста, без фокуса (вставка расшифровки).
    func testPanelExpandedWithDraftWithoutFocus() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: false, hasText: true), .full)
    }

    /// Фокус встал и текста нет — панель снова однострочная (клавиатуру
    /// свернули).
    func testCompactPanelReturnsWhenFocusLostAndNoText() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: false, hasText: false), .compact)
    }

    /// Текст есть — панель полная, даже если фокус ещё не вернулся.
    func testFullPanelWhenTextPresent() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .unified, isFocused: false, hasText: true), .full)
    }

    /// Родная панель всегда полная — удержание её не меняет.
    func testStandardStyleAlwaysFull() {
        XCTAssertEqual(ChatComposerLayoutPolicy.layout(style: .standard, isFocused: false, hasText: false), .full)
    }
}
