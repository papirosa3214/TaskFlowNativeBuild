import XCTest
final class SubtaskWorkPlanUITests: XCTestCase {
    func testInlineWorkPlanAndLiveUpdate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3320"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:work-task"
        app.launch()
        let toggle = app.buttons["subtask.work-plan-toggle.work-step"].firstMatch
        if !toggle.waitForExistence(timeout: 15) {
            let section = app.buttons["task-card.work-task.section.subtasks"]
            XCTAssertTrue(section.waitForExistence(timeout: 10), app.debugDescription)
            section.tap()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
        toggle.tap()
        let first = app.otherElements["work-plan.item.read"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(first.value as? String, "Выполнено")
        let current = app.otherElements["work-plan.item.make"].firstMatch
        XCTAssertEqual(current.value as? String, "Сейчас")
        capture(app, "Раскрытые этапы")
        let changed = expectation(description: "Fixture update")
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:3320/probe/update")!) { _,_,_ in changed.fulfill() }.resume()
        wait(for: [changed], timeout: 5)
        expectation(for: NSPredicate(format: "value == %@", "Выполнено"), evaluatedWith: current)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(app.otherElements["work-plan.item.verify"].firstMatch.value as? String, "Сейчас")
        capture(app, "Обновлённые этапы")
        toggle.tap()
        XCTAssertFalse(first.exists)
        capture(app, "Свёрнутая подзадача")
        toggle.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertEqual(current.value as? String, "Выполнено")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot());shot.name = name;shot.lifetime = .keepAlways;add(shot)
    }
}
