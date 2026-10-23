import XCTest

final class AIUsageUITests: XCTestCase {
    @MainActor func testOverviewUsageAndArchivedHistory() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launchArguments += ["-hints.enabled", "NO"]
        app.launch()
        let entry = app.buttons["Расход ИИ"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(app.segmentedControls["ai-usage.period"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Оценка стоимости"].waitForExistence(timeout: 20))
        app.segmentedControls["ai-usage.period"].buttons["Сегодня"].tap()
        XCTAssertTrue(app.staticTexts["Оценка стоимости"].waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ai-usage"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()
        let archive = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Архив:")).firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 15))
        archive.tap()
        let history = app.buttons["archive.completed-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        XCTAssertTrue(app.navigationBars["История выполнения"].waitForExistence(timeout: 10))
        let archiveShot = XCTAttachment(screenshot: app.screenshot())
        archiveShot.name = "completed-history"; archiveShot.lifetime = .keepAlways; add(archiveShot)
    }
}
