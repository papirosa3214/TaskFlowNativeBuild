import XCTest
final class HeatmapStyleUITests: XCTestCase {
    func testFlatSquareRedHeatmap() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let cell = app.buttons["overview.heatmap.cell.0"]
        XCTAssertTrue(cell.waitForExistence(timeout: 20))
        XCTAssertEqual(cell.frame.width,cell.frame.height,accuracy: 0.5)
        XCTAssertTrue(app.staticTexts["Меньше"].exists)
        XCTAssertTrue(app.staticTexts["Больше"].exists)
        XCTAssertFalse(app.staticTexts["12 недель"].exists)
        XCTAssertFalse(app.staticTexts["Выполненные задачи по дням"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="flat-red-square-heatmap";shot.lifetime = .keepAlways;add(shot)
    }
}
