import XCTest
final class OverviewFixedBarUITests: XCTestCase {
    func testAllButtonsStayFixedWhileMapExpands() {
        let app = XCUIApplication(); app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"; app.launch()
        let row = app.buttons["overview.weekly-summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let ids = ["tab.directory", "tab.projects", "tab.add", "tab.upcoming", "tab.chat"]
        let frames = ids.map { app.buttons[$0].frame }
        capture(app, "fixed-bar-before")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        let end = start.withOffset(CGVector(dx: 0, dy: 200))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Объёмная тепловая карта"].waitForExistence(timeout: 5))
        capture(app, "fixed-bar-expanded")
        for (index, id) in ids.enumerated() {
            XCTAssertEqual(app.buttons[id].frame.minY, frames[index].minY, accuracy: 0.5, id)
            XCTAssertEqual(app.buttons[id].frame.height, frames[index].height, accuracy: 0.5, id)
        }
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(app.staticTexts["Плоская тепловая карта"].waitForExistence(timeout: 5))
        for (index, id) in ids.enumerated() {
            XCTAssertEqual(app.buttons[id].frame.minY, frames[index].minY, accuracy: 0.5, id)
        }
        app.buttons["tab.add"].tap()
        XCTAssertTrue(app.buttons["create.task"].waitForExistence(timeout: 5))
        app.buttons["tab.add"].tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
