import XCTest

/// Временный тест (LOCK-TYPOGRAPHY-SPEC, этап А): кадр карточки задачи —
/// проверить иерархию (название крупнее заголовка секции) и масштабирование.
final class TypographyDefectsUITests: XCTestCase {
    func testCardHierarchyShot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()

        let project = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NewTodoist' ")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 25), "не нашёл проект")
        project.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Задачи' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "нет строки задачи")
        row.tap()

        // Карточка открывается шторкой: ждём её содержимое.
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "карточка задачи не открылась")
        sleep(2)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "task-card-typography"
        a.lifetime = .keepAlways
        add(a)
    }
}
