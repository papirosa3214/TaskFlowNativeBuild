import XCTest

/// Подпись работы роли: то же слово и тот же порядок у живого хода и в истории.
///
/// Владелец 10.11.2026: «как в T3 — работа свёрнута полосой, время тикает, но
/// не дёргает ленту». Тикающую подпись рисует отдельная вьюха, поэтому её
/// текст проверяется здесь, на хосте, — глазами на телефоне это не проверить.
final class RoleWorkFooterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @objc func testLiveWithoutSteps() {
        let text = RoleWorkFooter.text(state: "Работает", startedAt: start,
                                       steps: 0, now: start.addingTimeInterval(12))
        XCTAssertEqual(text, "Работает · " + RoleLiveFormat.duration(seconds: 12))
    }

    @objc func testLiveWithStepsKeepsOrder() {
        let text = RoleWorkFooter.text(state: "Работает", startedAt: start,
                                       steps: 5, now: start.addingTimeInterval(80))
        XCTAssertEqual(text, "Работает · " + RoleLiveFormat.duration(seconds: 80) + " · " + RoleLiveFormat.steps(5))
    }

    @objc func testFinishedStates() {
        XCTAssertTrue(RoleWorkFooter.text(state: "Ответ получен", startedAt: start,
                                          steps: 0, now: start.addingTimeInterval(3))
            .hasPrefix("Ответ получен"))
        XCTAssertTrue(RoleWorkFooter.text(state: "Остановлено", startedAt: start,
                                          steps: 2, now: start.addingTimeInterval(3))
            .hasPrefix("Остановлено"))
    }

    @objc func testNoStartMeansNoDuration() {
        let text = RoleWorkFooter.text(state: "Работает", startedAt: nil, steps: 0, now: start)
        XCTAssertEqual(text, "Работает")
    }

    @objc func testNegativeElapsedIsZero() {
        let text = RoleWorkFooter.text(state: "Работает", startedAt: start,
                                       steps: 0, now: start.addingTimeInterval(-30))
        XCTAssertEqual(text, "Работает · " + RoleLiveFormat.duration(seconds: 0))
    }

    @objc func testSummaryCountsSteps() {
        XCTAssertEqual(RoleWorkFooter.summary(stepCount: 7, thinkingSeconds: 0),
                       RoleLiveFormat.steps(7))
        XCTAssertEqual(RoleWorkFooter.summary(stepCount: 1, thinkingSeconds: 0), "1 шаг")
    }

    @objc func testSummaryAddsThinking() {
        let text = RoleWorkFooter.summary(stepCount: 3, thinkingSeconds: 60)
        XCTAssertEqual(text, "3 шага · думал " + RoleLiveFormat.duration(seconds: 60))
    }

    @objc func testSummaryWithoutThinking() {
        XCTAssertFalse(RoleWorkFooter.summary(stepCount: 2, thinkingSeconds: 0).contains("думал"))
    }

    @objc func testSummaryIsEmptyWhenNothingToShow() {
        XCTAssertEqual(RoleWorkFooter.summary(stepCount: 0, thinkingSeconds: 0), "")
    }

    @objc func testWorkShownOnlyWithDetailsAndOutsideSelection() {
        XCTAssertTrue(RoleWorkFooter.shouldShowWork(hasDetails: true, isSelecting: false))
        XCTAssertFalse(RoleWorkFooter.shouldShowWork(hasDetails: false, isSelecting: false))
        XCTAssertFalse(RoleWorkFooter.shouldShowWork(hasDetails: true, isSelecting: true))
    }
}
