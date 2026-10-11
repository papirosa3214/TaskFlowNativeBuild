import XCTest
final class OverviewActivityUITests: XCTestCase {
    func testHeatmapAndWeeklySummary() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        XCTAssertTrue(app.staticTexts["12 недель"].waitForExistence(timeout: 30), app.debugDescription)
        capture(app,"overview-heatmap")
        let summary = app.buttons["overview.weekly-summary"]
        if !summary.isHittable { app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        summary.tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 10))
        let productivity = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH[c] %@", "Продуктивность")).firstMatch
        let error = app.buttons["Повторить"]
        let finished = NSPredicate { _, _ in productivity.exists || error.exists }
        expectation(for: finished, evaluatedWith: nil)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(productivity.exists || error.exists)
        capture(app,"weekly-summary-live")
        app.buttons["Готово"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["projects.status.В работе"].exists)
        let overviewTitle = app.navigationBars.staticTexts["Обзор"].firstMatch
        XCTAssertLessThan(overviewTitle.frame.maxY, 170)
        app.buttons["tab.projects"].tap()
        let work = app.buttons["projects.status.В работе"]
        XCTAssertTrue(work.waitForExistence(timeout: 15), app.debugDescription)
        let noProject = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Без проекта")).firstMatch
        XCTAssertTrue(noProject.exists)
        XCTAssertLessThan(work.frame.minY, noProject.frame.minY)
        let title = app.navigationBars.staticTexts["Проекты"].firstMatch
        XCTAssertLessThan(title.frame.maxY, 170)
        capture(app,"projects-status-top-inline-title")
    }
    private func capture(_ app: XCUIApplication,_ name:String) {
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
