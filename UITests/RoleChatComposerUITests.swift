import XCTest

final class RoleChatComposerUITests: XCTestCase {
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
    func testStopInsideComposerPreservesDraftAndMode() {
        let app = launch()
        let stop = app.buttons["chat.stop"]
        XCTAssertTrue(stop.exists)
        let field = app.descendants(matching: .any).matching(identifier: "chat.message").firstMatch
        XCTAssertGreaterThan(stop.frame.midX, field.frame.midX)
        XCTAssertLessThan(abs(stop.frame.midY - field.frame.midY), 20)
        app.buttons["chat.mode"].tap()
        app.buttons["Глубокое исследование"].tap()
        XCTAssertTrue(app.buttons["chat.mode"].label.contains("Глубокое исследование"))
        field.tap(); field.typeText("Сравни варианты")
        XCTAssertTrue(stop.exists)
        capture(app, "composer-deep-research-stop-and-draft")
        stop.tap()
        XCTAssertTrue(app.buttons["chat.send"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Сравни варианты")
        XCTAssertTrue(app.buttons["chat.mode"].label.contains("Глубокое исследование"))
        capture(app, "composer-draft-after-stop")
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
