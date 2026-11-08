import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Куски для системного переводчика Apple и сборка показа.
///
/// Владелец 08.11.2026: «текста одно предложение и вообще полдня оно
/// переводится». Причина — в переводчик уходил весь текст реплики или
/// размышления целиком, а показ перевода ждал последнего куска. Отсюда правило:
/// текст режется на короткие куски, каждый кусок переводится отдельно, и показ
/// подставляет готовые куски по порядку, не дожидаясь остальных.
final class RoleTranslationChunksTests: XCTestCase {
    /// Короткий текст — один кусок, и склейка возвращает его же.
    @objc func testShortTextIsSingleChunk() {
        let text = "The role checks the server and writes the answer."
        let chunks = RoleTranslationChunks.of(text)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), text)
    }

    /// Длинный текст режется, но склейка совпадает с оригиналом знак в знак.
    @objc func testLongTextJoinsBackExactly() {
        let sentence = "The role checks the server and writes the answer for the owner. "
        let text = String(repeating: sentence, count: 40)
        let chunks = RoleTranslationChunks.of(text)
        XCTAssertGreaterThan(chunks.count, 1, "длинный текст обязан быть порезан")
        XCTAssertEqual(chunks.joined(), text)
        for chunk in chunks {
            XCTAssertFalse(chunk.isEmpty)
        }
    }

    /// Многострочный текст с пустыми строками и очень длинной строкой.
    @objc func testMultilineJoinsBackExactly() {
        let longLine = String(repeating: "проверяю ответ сервера ", count: 60)
        let text = "First line.\n\nSecond paragraph is short.\n\(longLine)\n\n\nLast line."
        XCTAssertEqual(RoleTranslationChunks.of(text).joined(), text)
    }

    /// Кириллица считается знаками, а не байтами: заниженный предел режет текст.
    @objc func testCyrillicIsCutByCharacters() {
        let text = String(repeating: "проверяю ", count: 80)
        let chunks = RoleTranslationChunks.of(text, limit: 100)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), text)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 100)
        }
    }

    /// Куски не зависят от прогона к прогону — иначе кэш перевода никогда не
    /// совпадёт и один и тот же абзац будет переводиться заново.
    @objc func testChunksAreStable() {
        let text = String(repeating: "The role reads the log file and reports the failure. ", count: 20)
        XCTAssertEqual(RoleTranslationChunks.of(text), RoleTranslationChunks.of(text))
    }

    /// Пока перевода нет, показывается оригинал — текст не пропадает.
    @objc func testShownIsOriginalWithoutTranslations() {
        let text = String(repeating: "The role checks the server. ", count: 30)
        XCTAssertEqual(RoleTranslationChunks.shown(text, translations: [:]), text)
    }

    /// Готовые куски показываются сразу, непереведённый хвост остаётся как был:
    /// читать русский до половины лучше, чем ждать весь текст.
    @objc func testShownReplacesReadyPrefixOnly() {
        let text = "First sentence here. Second sentence here. Third sentence here."
        let chunks = RoleTranslationChunks.of(text, limit: 40)
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        let translations = [chunks[0]: "Первый кусок переведён. "]
        let shown = RoleTranslationChunks.shown(text, translations: translations, limit: 40)
        XCTAssertTrue(shown.hasPrefix("Первый кусок переведён. "), shown)
        XCTAssertTrue(shown.hasSuffix(chunks.dropFirst().joined()), shown)
    }

    /// Все куски готовы — показ целиком на переводе.
    @objc func testShownIsFullyTranslatedWhenEverythingIsReady() {
        let text = "First sentence here. Second sentence here. Third sentence here."
        let chunks = RoleTranslationChunks.of(text, limit: 40)
        let translations = Dictionary(uniqueKeysWithValues: chunks.enumerated().map { index, chunk in
            (chunk, "R\(index) ")
        })
        XCTAssertEqual(RoleTranslationChunks.shown(text, translations: translations, limit: 40),
                       (0..<chunks.count).map { "R\($0) " }.joined())
    }

    /// Пустой текст — пустой список: незачем будить переводчик.
    @objc func testEmptyTextHasNoChunks() {
        XCTAssertEqual(RoleTranslationChunks.of(""), [])
        XCTAssertEqual(RoleTranslationChunks.shown("", translations: [:]), "")
    }
}
