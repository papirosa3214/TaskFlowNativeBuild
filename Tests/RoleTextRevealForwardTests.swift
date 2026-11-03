import XCTest
@testable import TaskFlow

/// Проявление ГОТОВОГО сообщения (владелец 31.10.2026): при входе в чат
/// ответ первую секунду рисуется разбитым на узкие колонки, с пропавшими
/// буквами. Причина — одна история проявления на всё дерево сообщения:
/// независимые `Text` (заголовки, пункты, подписи отчёта) делили один хвост,
/// и длина с индексами следующего текста брались из предыдущего.
///
/// Здесь — правило, которое это запрещает: у каждого независимого текста своё
/// проявление, буквы печатаются по порядку, а тексты идут друг за другом.
final class RoleTextRevealForwardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Готовое сообщение не появляется разом: первая буква ещё проявляется.
    func testReadyTextDoesNotAppearAtOnce() {
        let history = RoleTextRevealHistory()
        history.record(count: 40, now: start, rate: 10, animated: true, start: start)
        XCTAssertLessThan(history.opacity(at: 0, now: start), 1,
                          "готовый текст не должен появляться целиком сразу")
    }

    /// Второй независимый текст не наследует проявление первого.
    func testIndependentTextsDoNotShareRevealTail() {
        let history = RoleTextRevealHistory()
        history.record(count: 100, now: start, rate: 10, animated: true, start: start)
        history.record(count: 500, now: start, rate: 10, animated: true, start: start)
        XCTAssertLessThan(history.opacity(at: 0, now: start), 1,
                          "второй текст не должен начинать проявляться уже готовым")
    }

    /// Тексты сообщения проявляются по порядку: следующий ждёт конца первого.
    func testTextsRevealInOrder() {
        let history = RoleTextRevealHistory()
        history.record(count: 100, now: start, rate: 10, animated: true, start: start)
        history.record(count: 50, now: start, rate: 10, animated: true, start: start)
        // Перед вторым текстом 100 глифов первого — второй начинается позже.
        let t1 = start.addingTimeInterval(1)
        history.record(count: 100, now: t1, rate: 10, animated: true, start: start)
        history.record(count: 50, now: t1, rate: 10, animated: true, start: start)
        XCTAssertEqual(history.opacity(at: 0, now: t1), 0, accuracy: 0.0001)
    }

    /// Абзацы одной длины — разные тексты: второй ждёт первый, а не делит с ним
    /// хвост (владелец 03.11.2026: «на каждом блоке синхронно»).
    func testSameLengthTextsRevealSequentiallyNotInSync() {
        let history = RoleTextRevealHistory()
        history.record(count: 50, now: start, rate: 10, animated: true, start: start)
        history.record(count: 50, now: start, rate: 10, animated: true, start: start)
        // Через 2.5 с первый блок уже печатается; второй (offset 50) ещё молчит.
        // При ключе по длине оба делят одну историю — у «второго» первая буква
        // уже полностью видна, как у первого.
        let mid = start.addingTimeInterval(2.5)
        history.record(count: 50, now: mid, rate: 10, animated: true, start: start)
        history.record(count: 50, now: mid, rate: 10, animated: true, start: start)
        XCTAssertEqual(history.opacity(at: 0, now: mid), 0, accuracy: 0.0001,
                       "второй блок той же длины не должен проявляться вместе с первым")
        // Ровно когда очередь доходит до второго (50/10 = 5 с) — он только стартует.
        let afterFirst = start.addingTimeInterval(5.0)
        history.record(count: 50, now: afterFirst, rate: 10, animated: true, start: start)
        history.record(count: 50, now: afterFirst, rate: 10, animated: true, start: start)
        XCTAssertEqual(history.opacity(at: 0, now: afterFirst), 0, accuracy: 0.05)
    }

    /// Три коротких маркера (•) одной длины не стартуют fade разом.
    func testRepeatedSingleGlyphTextsStaySequential() {
        let history = RoleTextRevealHistory()
        history.record(count: 1, now: start, rate: 10, animated: true, start: start)
        history.record(count: 1, now: start, rate: 10, animated: true, start: start)
        history.record(count: 1, now: start, rate: 10, animated: true, start: start)
        let stillEarly = start.addingTimeInterval(0.15)
        history.record(count: 1, now: stillEarly, rate: 10, animated: true, start: start)
        history.record(count: 1, now: stillEarly, rate: 10, animated: true, start: start)
        history.record(count: 1, now: stillEarly, rate: 10, animated: true, start: start)
        // Третий маркер (offset 2) при rate 10 ждёт 0.2 с — на 0.15 ещё тишина.
        XCTAssertEqual(history.opacity(at: 0, now: stillEarly), 0, accuracy: 0.0001)
    }

    /// Блок, дорисованный на следующем кадре, продолжает очередь от начала
    /// сообщения (base = start), а не открывает параллельный fade с «сейчас».
    func testLateBlockContinuesGlobalSequence() {
        let history = RoleTextRevealHistory()
        history.record(count: 100, now: start, rate: 10, animated: true, start: start)
        let later = start.addingTimeInterval(2)
        history.record(count: 100, now: later, rate: 10, animated: true, start: start)
        history.record(count: 40, now: later, rate: 10, animated: true, start: start)
        // 100 глифов / 10 = 10 с — на 2-й секунде второй блок ещё не начался.
        XCTAssertEqual(history.opacity(at: 0, now: later), 0, accuracy: 0.0001)
        // Через 10 с от start очередь доходит до второго — он только стартует,
        // даже если блок впервые нарисовали на later.
        let atSecondStart = start.addingTimeInterval(10)
        history.record(count: 100, now: atSecondStart, rate: 10, animated: true, start: start)
        history.record(count: 40, now: atSecondStart, rate: 10, animated: true, start: start)
        XCTAssertEqual(history.opacity(at: 0, now: atSecondStart), 0, accuracy: 0.05)
        // Чуть позже второй уже проявляется (не остался навсегда прозрачным).
        let intoSecond = start.addingTimeInterval(10.4)
        history.record(count: 100, now: intoSecond, rate: 10, animated: true, start: start)
        history.record(count: 40, now: intoSecond, rate: 10, animated: true, start: start)
        XCTAssertGreaterThan(history.opacity(at: 0, now: intoSecond), 0.2)
    }
}
