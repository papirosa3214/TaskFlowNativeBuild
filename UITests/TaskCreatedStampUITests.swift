import XCTest

/// Временный тест (LOCK-TASK-CREATED-STAMP): дойти до списка задач проекта
/// и снять кадр строки с меткой даты заведения. Элементы ищутся по
/// accessibilityIdentifier/label — ручной тап по координатам скриншота
/// промахивается (points против пикселей ×3).
final class TaskCreatedStampUITests: XCTestCase {
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()
        return app
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Список задач КОНКРЕТНОГО проекта — то, о чём просил владелец:
    /// метка в списке, когда смотришь задачи внутри проекта.
    func testStampVisibleInProjectTaskList() {
        continueAfterFailure = false
        let app = makeApp()

        let project = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NewTodoist' ")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 25), "не нашёл проект TaskFlow — NewTodoist")
        project.tap()

        // Строка задачи — кнопка; ждём её, а не фиксированную паузу.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Задачи' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "в проекте не появилась строка задачи")

        // Метка — отдельный элемент с подписью VoiceOver «Заведена …».
        // Ищем по тому, что задаёт сам компонент: значит и шрифт, и разбор
        // даты отработали, а не просто вью пустая.
        let stamp = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Заведена'")).firstMatch
        XCTAssertTrue(
            stamp.waitForExistence(timeout: 10),
            "метка даты заведения не нашлась в списке задач проекра"
        )
        shoot(app, "project-task-list-stamp")
    }

    /// Тот же список с фильтром «Все» — там видны и выполненные задачи,
    /// метка должна быть и у них.
    func testStampOnCompletedTaskInProject() {
        continueAfterFailure = false
        let app = makeApp()

        let project = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NewTodoist' ")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 25))
        project.tap()

        let filter = app.buttons["Фильтр и действия"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20), "нет кнопки фильтра в шапке")
        filter.tap()

        let all = app.buttons["Все, включая выполненные"]
        XCTAssertTrue(all.waitForExistence(timeout: 10), "в меню фильтра нет пункта «Все»")
        all.tap()

        let stamp = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Заведена'")).firstMatch
        XCTAssertTrue(stamp.waitForExistence(timeout: 15), "метка не нашлась в фильтре «Все»")
        shoot(app, "project-task-list-all-stamp")
    }
}
