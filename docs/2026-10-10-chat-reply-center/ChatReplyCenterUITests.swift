import XCTest

final class ChatReplyCenterUITests: XCTestCase {
    func testReplyStartsInMiddleThenLongReplyFollowsBottom() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launch()
        let scroll = app.scrollViews["chat.message.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        func nearMiddle(_ text: XCUIElement) -> Bool {
            let predicate = NSPredicate { _, _ in
                text.exists && abs(text.frame.minY - scroll.frame.midY) < 70
            }
            return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10) == .completed
        }
        let short = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ответ начинается здесь.")).firstMatch
        XCTAssertTrue(nearMiddle(short), "Short reply starts near the middle of the chat viewport")
        let start = XCTAttachment(screenshot: app.screenshot()); start.name = "reply-middle"; start.lifetime = .keepAlways; add(start)
        app.buttons["Длинный ответ"].tap()
        let long = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "КОНЕЦ ДЛИННОГО ОТВЕТА")).firstMatch
        XCTAssertTrue(long.waitForExistence(timeout: 10))
        let composer = app.buttons["chat.mode"]
        let bottom = NSPredicate { _, _ in
            long.isHittable && composer.exists && long.frame.maxY < composer.frame.minY
                && composer.frame.minY - long.frame.maxY < 180
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: bottom, object: nil)], timeout: 10), .completed)
        let expanded = XCTAttachment(screenshot: app.screenshot()); expanded.name = "reply-long"; expanded.lifetime = .keepAlways; add(expanded)
        app.buttons["Завершить ответ"].tap()
        let completed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Короткий готовый результат.")).firstMatch
        XCTAssertTrue(nearMiddle(completed), "The completed short reply retains reading space")
        let final = XCTAttachment(screenshot: app.screenshot()); final.name = "reply-completed-middle"; final.lifetime = .keepAlways; add(final)
    }
}
