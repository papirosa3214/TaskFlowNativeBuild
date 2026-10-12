import XCTest
final class OverviewCompactUITests: XCTestCase {
    func testExpandedSectionsFitAboveFixedButtons() {
        let app = XCUIApplication(); app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"; app.launch()
        let row = app.buttons["overview.weekly-summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let barY = app.buttons["tab.directory"].frame.minY
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        capture(app, "compact-flat")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        let end = start.withOffset(CGVector(dx: 0, dy: 200))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Объёмная тепловая карта"].waitForExistence(timeout: 5))
        let settings = app.buttons.containing(.staticText, identifier: "Настройки").firstMatch
        XCTAssertTrue(settings.exists)
        XCTAssertLessThan(settings.frame.maxY, barY - 8)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        XCTAssertEqual(app.buttons["tab.directory"].frame.minY, barY, accuracy: 0.5)
        capture(app, "compact-expanded")
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(app.staticTexts["Плоская тепловая карта"].waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 5))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
