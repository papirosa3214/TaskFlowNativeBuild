import XCTest

final class PreparationActionsUITests: XCTestCase {
    func testPreparationScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_PREPARATION_PREVIEW"] = "executor"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:39fe9350-844b-40fe-8f44-b1343fed20f2"
        app.launch()
        let more = app.buttons["Ещё"]
        XCTAssertTrue(more.waitForExistence(timeout: 60))
        more.tap()
        let preparation = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Подготовка'")).firstMatch
        XCTAssertTrue(preparation.waitForExistence(timeout: 10))
        preparation.tap()
        XCTAssertTrue(app.staticTexts["Нужно уточнение"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["preparation.question"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["preparation.replyText"].exists)
        let builder = app.buttons["preparation.choice.builder"]
        XCTAssertTrue(builder.waitForExistence(timeout: 15))
        let next = app.buttons["preparation.continue"]
        XCTAssertTrue(next.isHittable, "Кнопка продолжения должна быть видна сразу")
        XCTAssertFalse(next.isEnabled)
        builder.tap()
        XCTAssertEqual(builder.value as? String, "Выбрано")
        XCTAssertTrue(next.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "preparation-ready-roles"
        shot.lifetime = .keepAlways
        add(shot)
        let scroll = app.scrollViews["preparation.content"]
        for _ in 0..<3 where !next.isHittable { scroll.swipeUp() }
        next.tap()
        XCTAssertTrue(app.staticTexts["Готовится"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["preparation.continue"].exists)
    }

    func testReadyStructureAnswerContinuesWithoutTyping() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_PREPARATION_PREVIEW"] = "structure"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:39fe9350-844b-40fe-8f44-b1343fed20f2"
        app.launch()
        let more = app.buttons["Ещё"]
        XCTAssertTrue(more.waitForExistence(timeout: 30)); more.tap()
        let preparation = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Подготовка'")).firstMatch
        XCTAssertTrue(preparation.waitForExistence(timeout: 10)); preparation.tap()
        let choice = app.buttons["preparation.choice.roles"]
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["preparation.replyText"].exists)
        choice.tap()
        let next = app.buttons["preparation.continue"]
        let scroll = app.scrollViews["preparation.content"]
        for _ in 0..<3 where !next.isHittable { scroll.swipeUp() }
        next.tap()
        XCTAssertTrue(app.staticTexts["Готовится"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["preparation.continue"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "preparation-answer-saved"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
