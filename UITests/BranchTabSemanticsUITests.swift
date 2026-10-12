import XCTest

final class BranchTabSemanticsUITests: XCTestCase {
    func testParentShowsBranchRolesAndState() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:71c1cd6e-ee8d-48ca-8a03-dc5723c958f7"
        app.launch()
        let plan = app.buttons["task-card.71c1cd6e-ee8d-48ca-8a03-dc5723c958f7.section.collaborationPlan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 60))
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "branch-parent-before"
        top.lifetime = .keepAlways
        add(top)
        let builder = app.buttons["plan-node-builder"]
        if !builder.exists { plan.tap() }
        XCTAssertTrue(builder.waitForExistence(timeout: 20))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "branch-graph-before"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(app.staticTexts["task.branch.status"].waitForExistence(timeout: 15), "Работа дочерних должна отражаться у родителя")
        XCTAssertTrue(app.staticTexts["branch.responsible"].exists, "Нужен ответственный за итог родителя")
        XCTAssertTrue(builder.label.contains("родительская вкладка"))
        let subtasks = app.buttons["task-card.71c1cd6e-ee8d-48ca-8a03-dc5723c958f7.section.subtasks"]
        let list = app.collectionViews["task.content.71c1cd6e-ee8d-48ca-8a03-dc5723c958f7"]
        for _ in 0..<6 where !subtasks.isHittable { list.swipeUp() }
        subtasks.tap()
        let role = app.staticTexts["subtask.role.cc1445cb-adb5-4c85-b3e7-4e9582d604a7"]
        for _ in 0..<3 where !role.exists { list.swipeUp() }
        XCTAssertTrue(role.waitForExistence(timeout: 10))
        XCTAssertEqual(role.label, "Разработчик")
        let rows = XCTAttachment(screenshot: app.screenshot())
        rows.name = "branch-local-roles"
        rows.lifetime = .keepAlways
        add(rows)
    }

    func testZNormalLaunchAfterVerification() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.buttons["tab.directory"].waitForExistence(timeout: 30))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "normal-launch"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
