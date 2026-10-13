import XCTest

/// Временный тест LOCK-ACTIVITY-CHART-TABS-20261013: вкладки графика в шапке.
final class ActivityChartTabsUITests: XCTestCase {
    func testTabsInHeaderCorner() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let stats = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Статистика")).firstMatch
        for _ in 0..<4 where !stats.waitForExistence(timeout: 5) || !stats.isHittable { app.swipeUp() }
        XCTAssertTrue(stats.waitForExistence(timeout: 20), app.debugDescription)
        stats.tap()

        let title = app.staticTexts["Продуктивность"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), app.debugDescription)
        let line = app.buttons["Кривая"].firstMatch
        let ring = app.buttons["Кольцо"].firstMatch
        XCTAssertTrue(line.exists && ring.exists)
        // Вкладки в одной строке с заголовком и справа от него.
        XCTAssertLessThan(abs(line.frame.midY - title.frame.midY), 20)
        XCTAssertGreaterThan(line.frame.minX, title.frame.maxX)
        shot(app, "01-line")
        ring.tap()
        shot(app, "02-ring")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
