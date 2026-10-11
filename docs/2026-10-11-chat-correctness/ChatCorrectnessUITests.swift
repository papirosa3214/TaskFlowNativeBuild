import XCTest

@available(iOS 26.0, *)
final class ChatCorrectnessUITests: XCTestCase {
    func testOrderedRepliesFinishWithoutWorkingArtifactsAndScrollPerformance() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_CHAT_ORDER_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_CHAT_CORRECTNESS_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["chat.preview.complete-both"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["chat.replyTo.question-1"].exists)
        XCTAssertTrue(app.staticTexts["chat.replyTo.question-2"].exists)
        XCTAssertTrue(app.staticTexts["Готовлю виджет…"].exists)
        XCTAssertTrue(app.staticTexts["Собираю интерактив…"].exists)
        app.buttons["chat.preview.end-live"].tap()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Работает")).count, 0)
        XCTAssertFalse(app.staticTexts["Готовлю виджет…"].exists)
        XCTAssertFalse(app.staticTexts["Собираю интерактив…"].exists)
        app.buttons["chat.preview.complete-both"].tap()
        XCTAssertFalse(app.staticTexts["Готовлю виджет…"].exists)
        XCTAssertFalse(app.staticTexts["Собираю интерактив…"].exists)
        XCTAssertTrue(app.staticTexts["Готовый виджет"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chat.replyTo.question-1"].exists)
        XCTAssertTrue(app.staticTexts["chat.replyTo.question-2"].exists)
        let interactive = app.webViews.buttons["Готовый интерактив"]
        XCTAssertTrue(interactive.waitForExistence(timeout: 5))
        interactive.tap()
        XCTAssertTrue(app.webViews.buttons["Нажато"].exists)
        app.buttons["chat.preview.complete-both"].tap()
        XCTAssertTrue(app.webViews.buttons["Нажато"].exists, "повторная доставка не пересоздаёт HTML")
        XCTAssertFalse(app.buttons["chat.stop"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Работает")).count, 0)
        let first = app.staticTexts["ПЕРВЫЙ ОТВЕТ"].firstMatch
        let second = app.staticTexts["ВТОРОЙ ОТВЕТ"].firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.exists)
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ordered-replies-completed-no-working-timer"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TASKFLOW_CHAT_CORRECTNESS_PREVIEW")
        app.launchEnvironment["TASKFLOW_CHAT_STRESS_PREVIEW"] = "1"
        app.launch()
        let feed = app.scrollViews["chat.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 20))
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            feed.swipeDown(velocity: .fast)
            feed.swipeDown(velocity: .fast)
            feed.swipeUp(velocity: .fast)
        }
    }
    func testLiveTextRenderingPerformance() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_CHAT_PACER_PREVIEW"] = "1"
        app.launch()
        let longReply = app.buttons["Длинный ответ"]
        XCTAssertTrue(longReply.waitForExistence(timeout: 15))
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            longReply.tap()
            let tail = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "КОНЕЦ ДЛИННОГО ОТВЕТА")).firstMatch
            XCTAssertTrue(tail.waitForExistence(timeout: 8))
        }
        app.buttons["Завершить ответ"].tap()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Работает")).count, 0)
    }

}
