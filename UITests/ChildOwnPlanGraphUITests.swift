import XCTest

/// Временный тест под задачу LOCK-CHILD-OWN-PLAN-GRAPH-20261008. После сверки удаляется.
final class ChildOwnPlanGraphUITests: XCTestCase {

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func openPlan(_ id: String, shotName: String) {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:\(id)"
        app.launch()
        let section = app.buttons["task-card.\(id).section.collaborationPlan"]
        XCTAssertTrue(section.waitForExistence(timeout:30), "секция не найдена: \(id)")
        if !app.otherElements["branch-plan.childGraph"].exists && !app.staticTexts["Общий план ветки"].exists { section.tap() }
        sleep(8)
        shot(app, shotName)
        let attempt0 = app.staticTexts["plan-attempt-0"]
        let attempt1 = app.staticTexts["plan-attempt-1"]
        let attempt2 = app.staticTexts["plan-attempt-2"]
        print("MARK \(shotName) a0=\(attempt0.exists) aI=\(attempt1.exists) aII=\(attempt2.exists)")
    }

    func testChildWithReturn() {
        openPlan("324f24ed-6b85-4cee-8099-71f5c0065ecb", shotName: "child-with-return")
    }

    func testParentRing() {
        openPlan("e34b032c-4aef-4d42-bd1d-1cf557d27c23", shotName: "parent-ring")
    }
}
