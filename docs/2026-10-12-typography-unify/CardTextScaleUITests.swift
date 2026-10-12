import XCTest

/// Временный тест (LOCK-TYPOGRAPHY-UNIFY): кадр карточки — название и
/// основные тексты 16, заголовки секций 13.
final class CardTextScaleUITests: XCTestCase {
    func testCardShot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()
        let project = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NewTodoist' ")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 25))
        project.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Задачи' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "card-text-scale"
        a.lifetime = .keepAlways
        add(a)
    }
}
