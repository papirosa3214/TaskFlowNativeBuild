import XCTest
/// Временный тест LOCK-TASK-CARD-CRASH-20261013: карточка открывается, секции на месте.
final class TaskCardOpenUITests: XCTestCase {
    func testCardOpens() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:kb-triage-mv5u7he1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Сведения"].waitForExistence(timeout: 30), app.debugDescription)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "card"; a.lifetime = .keepAlways; add(a)
    }
}
