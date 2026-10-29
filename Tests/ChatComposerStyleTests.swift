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
        XCTAssertEqual(ChatComposerStyle.resolve("classic"), .classic)
        XCTAssertEqual(ChatComposerStyle.resolve("unified"), .unified)
    }

    func testThreeVariantsWithTitlesAndNotes() {
        XCTAssertEqual(ChatComposerStyle.allCases.count, 3)
        XCTAssertEqual(ChatComposerStyle.allCases.map(\.title), ["Текущая", "Старая", "Новая"])
        XCTAssertTrue(ChatComposerStyle.allCases.allSatisfy { !$0.note.isEmpty })
    }

    func testDefaultIsCurrent() {
        XCTAssertEqual(ChatComposerStyle.defaultStyle, .standard)
    }

    func testStorageKeyIsStable() {
        XCTAssertEqual(ChatComposerStyle.storageKey, "taskflow_chat_composer_style")
    }

    func testOnlyOldVariantHidesToolChips() {
        XCTAssertFalse(ChatComposerStyle.classic.showsToolChips)
        XCTAssertTrue(ChatComposerStyle.standard.showsToolChips)
        XCTAssertTrue(ChatComposerStyle.unified.showsToolChips)
    }

    func testOnlyNewVariantUsesSingleRowLayout() {
        XCTAssertFalse(ChatComposerStyle.standard.isSingleRow)
        XCTAssertFalse(ChatComposerStyle.classic.isSingleRow)
        XCTAssertTrue(ChatComposerStyle.unified.isSingleRow)
    }
}
