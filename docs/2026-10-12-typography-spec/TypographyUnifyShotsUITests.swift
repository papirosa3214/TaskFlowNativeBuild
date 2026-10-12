import XCTest

/// Временный тест (LOCK-TYPOGRAPHY-UNIFY): кадры экранов после сведения
/// типографики на шкалу — проверить, что вид не поехал.
final class TypographyUnifyShotsUITests: XCTestCase {
    private func shoot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testListsCardAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()

        let project = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NewTodoist' ")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 25), "проекты не открылись")
        shoot("01-projects-list")

        project.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Задачи' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "список задач проекта не открылся")
        shoot("02-project-tasks")

        row.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "карточка не открылась")
        sleep(2)
        shoot("03-task-card")

        // Закрываем карточку и уходим в настройки.
        app.swipeDown()
        sleep(1)
        let gear = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Настройки' ")).firstMatch
        if gear.waitForExistence(timeout: 6) {
            gear.tap()
            sleep(2)
            shoot("04-settings")
        }
    }
}
