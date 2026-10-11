import XCTest
final class RoleChatStableFeedUITests: XCTestCase {
    func testTwoRoleOrderSurvivesCompletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_CHAT_ORDER_PREVIEW"] = "1"
        app.launch()
        let first = app.staticTexts["ПЕРВЫЙ ОТВЕТ ОРКЕСТРАТОРА"].firstMatch
        let second = app.staticTexts["ВТОРОЙ ОТВЕТ АРХИТЕКТОРА"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(second.exists)
        capture(app,"01-live-order")
        XCTAssertLessThan(first.frame.minY,second.frame.minY)
        app.buttons["chat.preview.finish-first"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertLessThan(first.frame.minY,second.frame.minY)
        capture(app,"02-completed-in-place")
    }
    private func capture(_ app: XCUIApplication,_ name:String) {
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
