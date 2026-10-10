import XCTest

final class TextFadeMonotonicUITests: XCTestCase {
    func testRichBlocksAppearWhileProseIsStillQueued() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_RICH_FAST_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Быстрый виджет"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Быстрый интерактив"].exists)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        let htmlButton = app.webViews.buttons["Проверить HTML"]
        XCTAssertTrue(htmlButton.waitForExistence(timeout: 5))
        htmlButton.tap()
        XCTAssertTrue(app.webViews.buttons["Нажато"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["chat.preview.complete"].exists)
        XCTAssertFalse(app.staticTexts["ХВОСТ ПОЯСНЕНИЯ"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "text-fade-interactive"; shot.lifetime = .keepAlways; add(shot)
    }
}
