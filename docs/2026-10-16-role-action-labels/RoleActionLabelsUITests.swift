import XCTest
final class RoleActionLabelsUITests: XCTestCase {
    private func verifyActions(_ app: XCUIApplication) {
        for title in ["Чтение", "Поиск", "Запись", "Правка", "Навык подключён", "Ошибка чтения навыка", "Тесты", "База знаний"] {
            let element = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 12), title + "\n" + app.debugDescription)
        }
        let skill = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Навык подключён")).firstMatch
        XCTAssertTrue(skill.label.contains("user-research"), skill.label)
        XCTAssertFalse(skill.label.contains("missing"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "action-labels"; shot.lifetime = .keepAlways; add(shot)
        skill.tap()
        XCTAssertTrue(app.staticTexts["Навык подключён"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/skills/user-research/SKILL.md")).firstMatch.exists)
    }
    func testChatActionLabels() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_ACTION_LABELS_PREVIEW"] = "1"
        app.launchArguments = ["-chat.workDetailLevel", "standard", "-hints.enabled", "NO"]
        app.launch()
        verifyActions(app)
    }
    func testGraphRoleActionLabels() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:energy"
        app.launchEnvironment["TASKFLOW_ACTION_LABELS_PREVIEW"] = "1"
        app.launchArguments = ["-chat.workDetailLevel", "standard", "-hints.enabled", "NO"]
        app.launch()
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 15)); grabber.swipeUp()
        let node = app.buttons["plan-node-builder"]
        if !node.exists { app.buttons["task-card.energy.section.collaborationPlan"].tap() }
        XCTAssertTrue(node.waitForExistence(timeout: 10))
        for _ in 0..<5 {
            if node.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(node.isHittable, app.debugDescription)
        node.tap()
        let window = app.scrollViews["plan-state-live"]
        let state = app.buttons["plan-state-live"]
        XCTAssertTrue(state.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Sheet Grabber"].swipeUp()
        let opened = XCTAttachment(screenshot: app.screenshot()); opened.name = "graph-role-opened"; opened.lifetime = .keepAlways; add(opened)
        if !window.waitForExistence(timeout: 3) {
            for _ in 0..<4 {
                if state.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(state.isHittable, app.debugDescription)
            state.tap()
        }
        XCTAssertTrue(window.waitForExistence(timeout: 10), app.debugDescription)
        verifyActions(app)
    }
}
