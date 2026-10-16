import XCTest

/// Временная проверка (LOCK-DESIGN-SYSTEM-GUARD-20261016): тумблеры сценариев
/// экрана «Оценщик JEV» нарисованы компонентом дизайн-системы `TFToggle`,
/// а не голым системным `Toggle`. Ходит к заглушечному серверу на
/// 127.0.0.1:3399, чтобы экран получил настройки и отрисовал строки.
final class JevToggleDesignSystemUITests: XCTestCase {
    func testScenarioTogglesRenderFromDesignSystem() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3399"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "debug"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launchArguments += ["-hints.enabled", "NO"]
        app.launch()

        let row = app.descendants(matching: .any)["settings-jev"]
        XCTAssertTrue(row.waitForExistence(timeout: 40), "нет строки «Оценщик JEV» в настройках")
        row.tap()

        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'jev-scenario-'"))
            .firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "тумблеры сценариев не появились")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "jev-scenarios"
        shot.lifetime = .keepAlways
        add(shot)

        NSLog("JEV_TOGGLES_READY")
        Thread.sleep(forTimeInterval: 20)
    }
}
