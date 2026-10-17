import XCTest
@testable import TaskFlow

/// Проявление текста в чате (17.10.2026). Здесь жил вылет приложения:
/// пока хвост ещё не осел, текст в чате растёт кадрами, и цикл добавления
/// новых глифов получал вывернутый диапазон — EXC_BREAKPOINT.
final class RoleTextRevealHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Сценарий падения: 100 глифов, хвост проявляется, текст вырос до 120.
    func testGrowingTextWhileTailStillAnimatingDoesNotTrap() {
        let history = RoleTextRevealHistory()
        history.record(count: 100, now: start, rate: 40, animated: true)
        history.record(count: 120, now: start.addingTimeInterval(0.1), rate: 40, animated: true)
        XCTAssertLessThanOrEqual(history.revealedUpTo, 120)
        // Ни один глиф не выходит за пределы текста и прозрачность в границах.
        for index in 0..<120 {
            let opacity = history.opacity(at: index, now: start.addingTimeInterval(0.2))
            XCTAssertGreaterThanOrEqual(opacity, 0)
            XCTAssertLessThanOrEqual(opacity, 1)
        }
    }

    /// Хвост продолжает оседать после роста текста, ничего не теряется.
    func testTailSettlesAfterGrowthAndEverythingBecomesVisible() {
        let history = RoleTextRevealHistory()
        history.record(count: 100, now: start, rate: 40, animated: true)
        history.record(count: 120, now: start.addingTimeInterval(0.05), rate: 40, animated: true)
        let later = start.addingTimeInterval(RoleTextFade.duration + 1)
        history.record(count: 120, now: later, rate: 40, animated: true)
        XCTAssertEqual(history.revealedUpTo, 120)
        for index in 0..<120 {
            XCTAssertEqual(history.opacity(at: index, now: later), 1, accuracy: 0.0001)
        }
    }

    /// Укорочение текста (перенос, правка) не оставляет хвост длиннее текста.
    func testShrinkingTextKeepsInvariant() {
        let history = RoleTextRevealHistory()
        history.record(count: 200, now: start, rate: 40, animated: true)
        history.record(count: 40, now: start.addingTimeInterval(0.02), rate: 40, animated: true)
        XCTAssertLessThanOrEqual(history.revealedUpTo, 40)
        for index in 0..<40 {
            XCTAssertLessThanOrEqual(history.opacity(at: index, now: start.addingTimeInterval(0.03)), 1)
        }
    }

    /// Чередование анимации и её окончания (реплика доехала, пришла новая).
    func testTogglingAnimationKeepsStateConsistent() {
        let history = RoleTextRevealHistory()
        history.record(count: 60, now: start, rate: 40, animated: true)
        history.record(count: 60, now: start.addingTimeInterval(0.1), rate: 40, animated: false)
        XCTAssertEqual(history.revealedUpTo, 60)
        history.record(count: 140, now: start.addingTimeInterval(0.2), rate: 40, animated: true)
        XCTAssertLessThanOrEqual(history.revealedUpTo, 140)
        let later = start.addingTimeInterval(RoleTextFade.duration + 2)
        history.record(count: 140, now: later, rate: 40, animated: true)
        XCTAssertEqual(history.revealedUpTo, 140)
    }

    /// Поток длинного ответа кадрами за 120 Гц — тот самый случай из чата.
    func testStreamingFramesDoNotTrap() {
        let history = RoleTextRevealHistory()
        let frame = 1.0 / 120.0
        for step in 1...600 {
            let now = start.addingTimeInterval(Double(step) * frame)
            history.record(count: step * 2, now: now, rate: 60, animated: true)
            for index in 0..<step * 2 {
                XCTAssertGreaterThanOrEqual(history.opacity(at: index, now: now), 0)
            }
        }
    }
}