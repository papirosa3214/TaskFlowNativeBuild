import Foundation
import XCTest
@testable import TaskFlow

/// Разбор сохранённого вида панели ввода (LOCK-CHAT-COMPOSER-STYLE-20261029).
final class ChatComposerStyleTests: XCTestCase {
    func testUnknownStoredValueFallsBackToCurrent() {
        XCTAssertEqual(ChatComposerStyle.resolve(nil), .standard)
        XCTAssertEqual(ChatComposerStyle.resolve(""), .standard)
        XCTAssertEqual(ChatComposerStyle.resolve("nonsense"), .standard)
    }

    func testKnownStoredValuesResolveToThemselves() {
        XCTAssertEqual(ChatComposerStyle.resolve("standard"), .standard)
        XCTAssertEqual(ChatComposerStyle.resolve("unified"), .unified)
    }

    func testTwoVariantsWithTitlesAndNotes() {
        XCTAssertEqual(ChatComposerStyle.allCases.count, 2)
        XCTAssertEqual(ChatComposerStyle.allCases.map(\.title), ["Родная", "Новая"])
        XCTAssertTrue(ChatComposerStyle.allCases.allSatisfy { !$0.note.isEmpty })
    }

    func testDefaultIsCurrent() {
        XCTAssertEqual(ChatComposerStyle.defaultStyle, .standard)
    }

    func testStorageKeyIsStable() {
        XCTAssertEqual(ChatComposerStyle.storageKey, "taskflow_chat_composer_style")
    }

    func testOnlyNewVariantUsesSingleRowLayout() {
        XCTAssertFalse(ChatComposerStyle.standard.isSingleRow)
        XCTAssertTrue(ChatComposerStyle.unified.isSingleRow)
    }
}
