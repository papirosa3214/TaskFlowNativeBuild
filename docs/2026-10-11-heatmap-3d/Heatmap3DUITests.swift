import XCTest
@available(iOS 26.0, *)
final class Heatmap3DUITests: XCTestCase {
    func testWholeScreenDragExpandsMapAndReturnsToOriginalLayout() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let row = app.buttons["overview.weekly-summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let original = row.frame
        XCTAssertTrue(app.staticTexts["Плоская тепловая карта"].exists)
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        let end = start.withOffset(CGVector(dx: 0, dy: 200))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Объёмная тепловая карта"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(row.frame.minY, original.minY + 100)
        var shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "overview-3d"; shot.lifetime = .keepAlways; add(shot)
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(app.staticTexts["Плоская тепловая карта"].waitForExistence(timeout: 5))
        XCTAssertEqual(row.frame.minY, original.minY, accuracy: 1)
        shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "overview-returned-flat"; shot.lifetime = .keepAlways; add(shot)
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 5), "обычные нажатия не перехватываются жестом")
    }
    func testOverviewGesturePerformance() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let row = app.buttons["overview.weekly-summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        let end = start.withOffset(CGVector(dx: 0, dy: 200))
        let options = XCTMeasureOptions(); options.iterationCount = 1
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            for _ in 0..<3 {
                start.press(forDuration: 0.05, thenDragTo: end)
                end.press(forDuration: 0.05, thenDragTo: start)
            }
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "overview-flat"; shot.lifetime = .keepAlways; add(shot)
    }
}
