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
        XCTAssertTrue(app.staticTexts["Месяцы над картой"].exists)
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        let end = start.withOffset(CGVector(dx: 0, dy: 200))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Объёмная тепловая карта"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Месяцы вдоль нижнего края карты"].exists)
        XCTAssertGreaterThan(row.frame.minY, original.minY + 80)
        var shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "overview-3d"; shot.lifetime = .keepAlways; add(shot)
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(app.staticTexts["Плоская тепловая карта"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Месяцы над картой"].exists)
        XCTAssertEqual(row.frame.minY, original.minY, accuracy: 1)
        shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "overview-returned-flat"; shot.lifetime = .keepAlways; add(shot)
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 5), "обычные нажатия не перехватываются жестом")
    }
    func testRecordBadgeFillsTheEmptyCornerOnlyWhenExpanded() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let row = app.buttons["overview.weekly-summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let record = app.descendants(matching: .any).matching(identifier: "overview.heatmap.record").firstMatch
        XCTAssertFalse(record.exists, "в плоской карте бейдж не должен занимать место в углу")

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        let end = start.withOffset(CGVector(dx: 0, dy: 200))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Объёмная тепловая карта"].waitForExistence(timeout: 5))
        let png = app.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/tmp/heatmap-badge.png"))
        if !record.waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "heatmap-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(record.exists, "цифра рекорда не появилась в освободившемся углу")

        var shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "overview-3d-record"; shot.lifetime = .keepAlways; add(shot)
        // Бейдж лежит поверх сцены и не должен съедать обычные нажатия.
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 5), "бейдж перехватил тап по строке меню")
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
