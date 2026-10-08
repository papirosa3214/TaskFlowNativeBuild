import XCTest

final class OwnerCommandUITests: XCTestCase {
    func testConfirmCancelAndLiveResult() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_OWNER_COMMAND_PREVIEW"] = "printf 'TaskFlow Play OK'"
        app.launch()
        let play = app.buttons["chat-command-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        play.tap()
        XCTAssertTrue(app.buttons["chat-command-confirm"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
        XCTAssertFalse(app.staticTexts["chat-command-result"].exists)
        play.tap()
        app.buttons["chat-command-confirm"].tap()
        XCTAssertTrue(app.staticTexts["chat-command-result"].waitForExistence(timeout: 40), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Код завершения: 0"].exists)
        XCTAssertTrue(app.staticTexts["TaskFlow Play OK"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "owner-command-live-result"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
