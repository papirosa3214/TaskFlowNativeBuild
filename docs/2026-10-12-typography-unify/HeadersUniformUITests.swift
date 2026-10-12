import XCTest

/// Временный тест (LOCK-TYPOGRAPHY-UNIFY): заголовки секций сведены к одному
/// виду — большинству. Кадры «Сегодня» и карточки.
final class HeadersUniformUITests: XCTestCase {
    func testTodayAndCardHeaders() {
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
        a.name = "task-card-headers"
        a.lifetime = .keepAlways
        add(a)
    }
}
