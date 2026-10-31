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
        history.record(count: 40, now: start, rate: 10, animated: true)
        XCTAssertLessThan(history.opacity(at: 0, now: start), 1,
                          "готовый текст не должен появляться целиком сразу")
    }

    /// Второй независимый текст не наследует проявление первого.
    func testIndependentTextsDoNotShareRevealTail() {
        let history = RoleTextRevealHistory()
        history.record(count: 100, now: start, rate: 10, animated: true)
        history.record(count: 500, now: start, rate: 10, animated: true)
        XCTAssertLessThan(history.opacity(at: 0, now: start), 1,
                          "второй текст не должен начинать проявляться уже готовым")
    }

    /// Тексты сообщения проявляются по порядку: следующий ждёт конца первого.
    func testTextsRevealInOrder() {
        let history = RoleTextRevealHistory()
        history.record(count: 100, now: start, rate: 10, animated: true)
        history.record(count: 50, now: start, rate: 10, animated: true)
        // Перед вторым текстом 100 глифов первого — второй начинается позже.
        XCTAssertEqual(history.opacity(at: 0, now: start.addingTimeInterval(1)), 0,
                       accuracy: 0.0001)
    }
}
