import XCTest

/// Временный тест LOCK-ESCALATION-SETTINGS-20261013: экран напоминаний о просрочке.
final class EscalationSettingsUITests: XCTestCase {
    func testEscalationSettingsScreen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launch()

        let row = app.descendants(matching: .any)["settings-escalation"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "нет строки в настройках")
        row.tap()

        let toggle = app.descendants(matching: .any)["escalation-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "экран не открылся")
        let step = app.buttons["escalation-step-0"]
        XCTAssertTrue(step.waitForExistence(timeout: 10), "нет шагов")
        XCTAssertTrue(app.buttons["escalation-day-1"].exists)
        shot(app, "01-screen")

        step.tap()
        XCTAssertTrue(app.descendants(matching: .any)["escalation-step-hours"].waitForExistence(timeout: 5))
        shot(app, "02-step-editor")
        app.buttons["Отмена"].tap()

        // Выключить — разделы прячутся; включить обратно — правило восстановлено.
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(step.waitForNonExistence(timeout: 10), "после выключения шаги видны")
        shot(app, "03-disabled")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(step.waitForExistence(timeout: 10), "после включения шагов нет")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
