import XCTest

final class RoleBehaviorUITests: XCTestCase {
    private func openBehavior(_ app: XCUIApplication, conflict: Bool = false) {
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "agents"
        app.launchEnvironment["TASKFLOW_ROLE_CONTEXT_FIXTURE"] = "1"
        if conflict { app.launchEnvironment["TASKFLOW_ROLE_BEHAVIOR_CONFLICT"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["team-menu"].waitForExistence(timeout: 30))
        let role = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Разработчик'")).firstMatch
        XCTAssertTrue(role.waitForExistence(timeout: 20)); role.tap()
        let context = app.buttons["Как запускается роль"]
        // The role editor places this row after its instruction field; reach it by semantics.
        for _ in 0..<6 {
            if context.exists && context.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(context.waitForExistence(timeout: 10)); context.tap()
        let behavior = app.buttons["roleContext.behavior"]
        XCTAssertTrue(behavior.waitForExistence(timeout: 10)); behavior.tap()
        XCTAssertTrue(app.textViews["roleBehavior.editor"].waitForExistence(timeout: 10))
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let element = app.buttons[id]
        for _ in 0..<8 {
            if element.exists && element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("Button not reachable: \(id)")
    }
    private func goToTop(_ app: XCUIApplication) { for _ in 0..<7 { app.swipeDown() } }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSaveTemplateDoesNotApplyThenApplyRetainsFemaleGender() {
        let app = XCUIApplication(); openBehavior(app)
        tap("roleBehavior.gender", app: app)
        app.buttons["Женский"].tap()
        tap("roleBehavior.template.warm", app: app)
        let name = app.textFields["roleBehavior.templateName"]
        for _ in 0..<5 { if name.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(name.exists); name.tap(); name.typeText("Мой характер")
        app.swipeUp()
        tap("roleBehavior.saveTemplate", app: app)
        XCTAssertTrue(app.staticTexts["Шаблон сохранён. Действующая личность не изменена."].waitForExistence(timeout: 10))
        goToTop(app)
        XCTAssertTrue(app.staticTexts["roleBehavior.activeText"].label.contains("разработчик"))
        tap("roleBehavior.apply", app: app)
        goToTop(app)
        XCTAssertEqual(app.staticTexts["roleBehavior.activeGender"].label, "Пол: Женский")
        XCTAssertTrue(app.staticTexts["roleBehavior.activeText"].label.contains("тёплый партнёр"))
        capture(app, name: "role-behavior-applied-female")
    }
    func testConflictKeepsDraftAndGenderUntilExplicitApply() {
        let app = XCUIApplication(); openBehavior(app, conflict: true)
        tap("roleBehavior.template.warm", app: app)
        goToTop(app); tap("roleBehavior.apply", app: app)
        tap("roleBehavior.refreshVersion", app: app)
        goToTop(app)
        let editor = app.textViews["roleBehavior.editor"]
        XCTAssertTrue((editor.value as? String ?? "").contains("тёплый партнёр"))
        XCTAssertEqual(app.staticTexts["roleBehavior.activeGender"].label, "Пол: Мужской")
        tap("roleBehavior.apply", app: app); goToTop(app)
        XCTAssertEqual(app.staticTexts["roleBehavior.activeGender"].label, "Пол: Женский")
        capture(app, name: "role-behavior-conflict-recovered")
    }
}
