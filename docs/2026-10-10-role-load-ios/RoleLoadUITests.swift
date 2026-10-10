import XCTest
final class RoleLoadUITests: XCTestCase {
    func testLiveRoleLoad() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
        app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3318"
        app.launch()
        let entry = app.buttons["overview.role-load"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), app.debugDescription)
        entry.tap()
        let chart = app.otherElements["role-load.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 30), app.debugDescription)
        capture(app, "Сутки")
        app.segmentedControls.buttons["Неделя"].tap()
        expectation(for: NSPredicate(format: "value == %@", "week"), evaluatedWith: chart)
        waitForExpectations(timeout: 15)
        capture(app, "Неделя")
        let task = app.buttons["Сейчас · Проверка загрузки ролей"].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10), app.debugDescription)
        app.scrollViews["role-load.timeline"].swipeLeft()
        task.tap()
        XCTAssertTrue(app.buttons["task-card.load-test.section.details"].waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "Карточка задачи")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
