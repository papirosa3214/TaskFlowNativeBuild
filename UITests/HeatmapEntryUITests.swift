import XCTest
@available(iOS 26.0, *)
final class HeatmapEntryUITests: XCTestCase {
    func testEntryRangePerformance() { measureEntry(distance: 13, repetitions: 10) }
    func testInitialThirtyPercentPerformance() { measureEntry(distance: 39, repetitions: 6) }

    private func measureEntry(distance: CGFloat, repetitions: Int) {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let row = app.buttons["overview.weekly-summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        let options = XCTMeasureOptions(); options.iterationCount = 1
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            for _ in 0..<repetitions {
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 15), thenHoldForDuration: 0.15)
            }
        }
        XCTAssertTrue(app.staticTexts["Плоская тепловая карта"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "entry-returned-flat"; shot.lifetime = .keepAlways; add(shot)
    }
}
