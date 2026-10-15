import XCTest

/// Режим подсказок (LOCK-HINTS-ONBOARDING-20261016): тумблер в настройках,
/// запуск сценария, ветка по выбору, выход по «Пропустить».
final class HintsUITests: XCTestCase {
    func testEnableRunBranchAndSkip() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launchArguments += ["-hints.enabled", "NO", "-hints.completed", "()", "-settings.user.expanded", "YES"]
        app.launch()

        let toggle = app.switches["settings.hints"].exists ? app.switches["settings.hints"] : app.descendants(matching: .any)["settings.hints"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        toggle.tap()

        let scenario = app.buttons["settings.hints.task-plan"]
        XCTAssertTrue(scenario.waitForExistence(timeout: 5))
        scenario.tap()

        let card = app.descendants(matching: .any)["hint.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["hint.next"].tap()

        let branch = app.buttons["hint.branch.Подзадачи уже написаны"]
        XCTAssertTrue(branch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["hint.branch.Подзадач нет"].exists)
        branch.tap()
        XCTAssertTrue(app.staticTexts["Собрать план из подзадач"].waitForExistence(timeout: 5))

        app.buttons["hint.skip"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["settings.hints.task-plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.hints.task-plan"].label.contains("заново"))
    }
}
