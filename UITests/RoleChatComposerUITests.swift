import XCTest

final class RoleChatComposerUITests: XCTestCase {
    func testExecutionChoiceIsInsideWorkMenuAndPreservesDraft() {
        for promptBox in ["YES", "NO"] {
            let app = XCUIApplication()
            app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
            app.launchArguments = ["-chat.experimentalPromptBox", promptBox]
            app.launch()
            let menu = app.buttons["chat.mode"]
            XCTAssertTrue(menu.waitForExistence(timeout: 20))
            XCTAssertFalse(app.segmentedControls["chat.execution-mode"].exists)
            let field = app.descendants(matching: .any).matching(identifier: "chat.message").firstMatch
            field.tap()
            field.typeText("keep this draft")
            menu.tap()
            let card = app.buttons["По карточке"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            guard card.exists else { app.terminate(); return }
            card.tap()
            XCTAssertEqual(menu.value as? String, "По карточке")
            XCTAssertEqual(field.value as? String, "keep this draft")
            menu.tap()
            app.buttons["В чате"].tap()
            XCTAssertEqual(menu.value as? String, "В чате")
            XCTAssertEqual(field.value as? String, "keep this draft")
            app.terminate()
        }
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["chat.mode"].waitForExistence(timeout: 20))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    /// Пока роль отвечает, в поле ввода нет квадрата «Стоп»: остановка — в
    /// пилюле над полем. Справа микрофон, с текстом — отправка; черновик
    /// не теряется (владелец 11.11.2026).
    func testNoStopInComposerWhileResponding() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launch()
        let field = app.descendants(matching: .any).matching(identifier: "chat.message").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["chat.stop"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.voice").firstMatch.exists)
        field.tap(); field.typeText("Сравни варианты")
        XCTAssertTrue(app.buttons["chat.send"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.stop"].exists)
        XCTAssertEqual(field.value as? String, "Сравни варианты")
        capture(app, "composer-responding-no-stop")
    }
    func testPlanningAndStreamingCompletion() {
        let app = launch()
        app.buttons["chat.mode"].tap()
        app.buttons["Планирование"].tap()
        XCTAssertTrue(app.buttons["chat.mode"].label.contains("Планирование"))
        XCTAssertTrue(app.staticTexts["chat.preview.complete"].waitForExistence(timeout: 20))
        capture(app, "composer-planning-completed-stream")
    }
}
