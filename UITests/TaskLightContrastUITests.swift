import XCTest

final class TaskLightContrastUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testLiveTaskCardLightWindows() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Обзор"].waitForExistence(timeout: 40))
        app.buttons["Обзор"].tap()
        let settings = app.staticTexts["Настройки"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        let theme = app.switches["settings.appearance"]
        XCTAssertTrue(theme.waitForExistence(timeout: 15))
        if theme.value as? String != "0" { theme.tap() }
        app.buttons["BackButton"].tap()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "На проверке")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        let row = app.scrollViews.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "на проверке")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["task.title.content"].waitForExistence(timeout: 20))
        capture(app, "light-task-medium")
        let description = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".section.description")).firstMatch
        let identifier = description.identifier
        let taskID = String(identifier.dropFirst("task-card.".count).dropLast(".section.description".count))
        XCTAssertFalse(taskID.isEmpty)
        app.terminate()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:\(taskID)"
        app.launchArguments = ["-task.card.sections.\(taskID)", "(details,subtasks,linkedTasks,outcome,journal)"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["task.title.content"].waitForExistence(timeout: 20))
        if app.buttons["Sheet Grabber"].exists { app.buttons["Sheet Grabber"].swipeUp() }
        capture(app, "light-task-details")
        let outcome = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Подтвердить первоисточник")).firstMatch
        if outcome.exists && outcome.isHittable {
            outcome.tap()
            XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 10))
            capture(app, "light-task-outcome-sheet")
            app.buttons["Готово"].tap()
        }
        app.buttons["Ещё"].tap()
        let link = app.buttons["Связать существующую задачу"]
        XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        XCTAssertTrue(app.navigationBars["Связать задачу"].waitForExistence(timeout: 10))
        capture(app, "light-task-link-picker")
        app.buttons["Отмена"].firstMatch.tap()
        app.swipeUp(); capture(app, "light-task-subtasks")
        app.swipeUp(); capture(app, "light-task-journal")
        app.terminate()
        app.launchArguments = ["-task.card.sections.\(taskID)", "(description)"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["task.title.content"].waitForExistence(timeout: 20))
        if app.buttons["Sheet Grabber"].exists { app.buttons["Sheet Grabber"].swipeUp() }
        capture(app, "light-task-description")
    }

    func testPlanStepSheetWithLocalFixture() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:branch"
        app.launchArguments = ["-taskflow_appearance", "light", "-task.card.sections.branch", "(description,details,collaborationPlan,subtasks,journal)"]
        app.launch()
        XCTAssertTrue(app.buttons["Sheet Grabber"].waitForExistence(timeout: 20))
        app.buttons["Sheet Grabber"].swipeUp()
        let arm = app.buttons["task.arm.details"]
        if arm.exists && arm.isHittable {
            arm.tap()
            app.buttons["task.edit.details"].tap()
            let due = app.buttons["Не установлен"].firstMatch
            XCTAssertTrue(due.waitForExistence(timeout: 5)); due.tap()
            capture(app, "light-task-date-editor-fixture")
            let today = app.buttons["Сегодня"].firstMatch
            XCTAssertTrue(today.waitForExistence(timeout: 5)); today.tap()
        }
        let node = app.buttons["plan-node-builder"]
        XCTAssertTrue(node.waitForExistence(timeout: 15)); node.tap()
        XCTAssertTrue(app.buttons["plan-state-live"].waitForExistence(timeout: 10))
        capture(app, "light-plan-step-fixture")
        if !app.staticTexts["Проверяю источники"].exists { app.buttons["plan-state-live"].tap() }
        XCTAssertTrue(app.staticTexts["Проверяю источники"].waitForExistence(timeout: 10))
        capture(app, "light-plan-step-activity-fixture")
        app.swipeUp(); capture(app, "light-plan-step-result-fixture")
        app.terminate()
        app.launchEnvironment = [:]; app.launchArguments = []; app.launch()
    }
}
