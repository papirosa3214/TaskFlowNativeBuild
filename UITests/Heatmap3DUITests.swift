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
        let today = app.descendants(matching: .any).matching(identifier: "overview.heatmap.today").firstMatch
        XCTAssertFalse(record.exists, "в плоской карте бейдж не должен занимать место в углу")
        XCTAssertFalse(today.exists, "показатель за сегодня виден только в 3D")

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
        XCTAssertTrue(today.waitForExistence(timeout: 5), "цифра за сегодня не появилась в правом верхнем углу")
        XCTAssertTrue(today.label.contains("на проверку"), "метрика сегодняшнего значения должна быть доступна VoiceOver")
        XCTAssertTrue(today.label.contains("Сегодня"), "показатель за сегодня должен иметь понятную подпись")

        var shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "overview-3d-record"; shot.lifetime = .keepAlways; add(shot)
        // Бейдж лежит поверх сцены и не должен съедать обычные нажатия.
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 5), "бейдж перехватил тап по строке меню")
    }

    func testSelectingHeatmapDayShowsItsCount() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let row = app.buttons["overview.weekly-summary"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 200)))
        XCTAssertTrue(app.staticTexts["Объёмная тепловая карта"].waitForExistence(timeout: 5))
        let day = app.buttons["overview.heatmap.cell.170"]
        XCTAssertTrue(day.waitForExistence(timeout: 20))
        day.tap()
        let detailDate = app.staticTexts["overview.heatmap.selection.date"]
        let detailCount = app.staticTexts["overview.heatmap.selection.count"]
        XCTAssertTrue(detailDate.waitForExistence(timeout: 5))
        XCTAssertTrue(detailCount.waitForExistence(timeout: 5))
        let record = app.descendants(matching: .any).matching(identifier: "overview.heatmap.record").firstMatch
        let today = app.descendants(matching: .any).matching(identifier: "overview.heatmap.today").firstMatch
        XCTAssertTrue(record.exists)
        XCTAssertTrue(today.exists)
        let labelBounds = detailDate.frame.union(detailCount.frame).insetBy(dx: -4, dy: -2)
        XCTAssertFalse(labelBounds.intersects(record.frame), "дата и число не должны закрывать рекорд тепловой карты")
        XCTAssertFalse(labelBounds.intersects(today.frame), "дата и число не должны закрывать показатель за сегодня")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "overview-heatmap-selected-day"
        shot.lifetime = .keepAlways
        add(shot)
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
