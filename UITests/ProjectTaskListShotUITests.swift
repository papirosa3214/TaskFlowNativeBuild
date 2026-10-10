import XCTest

/// Временный тест: снять кадр каноничного списка задач внутри проекта.
final class ProjectTaskListShotUITests: XCTestCase {
    func testOpenProjectAndShoot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()
        // Первый проект в списке — самый верхний заголовок-строка.
        let first = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NewTodoist' ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 25), "не нашёл проект TaskFlow — NewTodoist")
        first.tap()
        usleep(2_500_000)
        // Ждём появления строки задачи: заголовок списка задач виден как кнопка.
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Задачи' ")).firstMatch.waitForExistence(timeout: 15)
        usleep(1_500_000)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "project-task-list"
        a.lifetime = .keepAlways
        add(a)
    }
}