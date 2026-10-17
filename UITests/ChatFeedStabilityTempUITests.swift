import XCTest

final class ChatFeedStabilityTempUITests: XCTestCase {
    func testLongLiveReplyRemainsVisibleThroughPacedPlayback() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_CHAT_PACER_PREVIEW"] = "1"
        app.launch()

        let feed = app.scrollViews["chat.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 20))

        let start = app.buttons["Длинный ответ"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let firstText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ответ начинается здесь.")).firstMatch
        XCTAssertTrue(firstText.waitForExistence(timeout: 10))
        let earlyFrame = firstText.frame
        let early = XCTAttachment(screenshot: app.screenshot())
        early.name = "chat-feed-live-reply-start"
        early.lifetime = .keepAlways
        add(early)

        let finish = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "КОНЕЦ ДЛИННОГО ОТВЕТА")).firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        XCTAssertTrue(feed.exists, "Лента остаётся в иерархии, пока живой ответ растёт")
        XCTAssertGreaterThan(firstText.frame.height, earlyFrame.height - 1)

        let completed = XCTAttachment(screenshot: app.screenshot())
        completed.name = "chat-feed-live-reply-end"
        completed.lifetime = .keepAlways
        add(completed)
    }
}
