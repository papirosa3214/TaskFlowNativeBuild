import XCTest

final class SlowStreamUITests: XCTestCase {
    func testBurstDrainsTextThenActionsBeforeCompletion() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_SMOOTH_STREAM_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["chat.mode"].waitForExistence(timeout: 45))
        let complete = app.staticTexts["chat.preview.complete"]
        XCTAssertFalse(complete.exists, "Завершение ждёт очередь")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Файл 1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 45))
        let progress = XCTAttachment(screenshot: app.screenshot())
        progress.name = "smooth-stream-actions"; progress.lifetime = .keepAlways; add(progress)
        XCTAssertTrue(complete.waitForExistence(timeout: 45))
        for number in 1...4 {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Файл \(number)")).firstMatch.exists)
        }
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "smooth-stream-complete"; result.lifetime = .keepAlways; add(result)
    }
}
