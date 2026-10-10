import XCTest

final class PromptBoxUITests: XCTestCase {
    func testInputAndRestore() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_PROMPT_BOX_PREVIEW"] = "1"
        app.launch()
        let input = app.descendants(matching: .any)["chat.message"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let experimentalWidth = input.frame.width
        input.tap()
        input.typeText("Пробное сообщение")
        XCTAssertTrue(app.buttons["chat.send"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Экспериментальное поле"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat.voice"].waitForExistence(timeout: 5))
        app.buttons["chat.attachment"].tap()
        app.buttons["Экспериментальное поле"].tap()
        XCTAssertTrue(app.buttons["chat.mode"].waitForExistence(timeout: 5))
        let restoredWidth = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in input.frame.width < experimentalWidth - 20 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredWidth], timeout: 5), .completed)
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "Текущее поле восстановлено"
        restored.lifetime = .keepAlways
        add(restored)
    }
}
