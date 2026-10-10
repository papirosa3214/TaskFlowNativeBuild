import XCTest

final class TaskPreparationReplyUITests: XCTestCase {
    func testChooseAnswerWithoutTypingAndResumePreparation() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:energy"
        app.launch()
        let more = app.buttons["Ещё"]
        XCTAssertTrue(more.waitForExistence(timeout: 20)); more.tap()
        let preparation = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Подготовка")).firstMatch
        XCTAssertTrue(preparation.waitForExistence(timeout: 5)); preparation.tap()
        let reply = app.buttons["preparation.reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 10)); reply.tap()
        for key in ["children", "roles", "steps"] {
            XCTAssertTrue(app.buttons["preparation.choice." + key].waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.textFields["preparation.replyText"].exists)
        let options = XCTAttachment(screenshot: app.screenshot()); options.name = "preparation-answer-options"; options.lifetime = .keepAlways; add(options)
        app.buttons["preparation.choice.roles"].tap()
        XCTAssertTrue(app.staticTexts["Готовится"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["preparation.reply"].exists)
        let resumed = XCTAttachment(screenshot: app.screenshot()); resumed.name = "preparation-resumed"; resumed.lifetime = .keepAlways; add(resumed)
    }
}
