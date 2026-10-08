import XCTest

final class ServerSettingsUITests: XCTestCase {
    private func openSettings(fixture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        if fixture { app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1" }
        app.launch()
        let row = app.buttons["settings-server-parameters"]
        for _ in 0..<8 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        row.tap()
        return app
    }
    func testReadableTimeUnits() {
        continueAfterFailure = false
        let app = openSettings(fixture: false)
        let probe = app.buttons["server-setting-provider_probe_interval_ms"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20))
        XCTAssertTrue(probe.staticTexts["5 мин"].exists)
        let pause = app.buttons["server-setting-slot_stop_summary_ms"]
        XCTAssertTrue(pause.staticTexts["30 с"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "server-settings-readable-time-units"
        shot.lifetime = .keepAlways
        add(shot)
        pause.tap()
        let input = app.textFields["server-setting-value"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "30")
        XCTAssertTrue(app.staticTexts["Единица: с"].exists)
        XCTAssertTrue(app.staticTexts["По умолчанию: 30 с"].exists)
    }
    func testPrimaryNumericSaveResetAndBoolean() {
        continueAfterFailure = false
        let app = openSettings(fixture: false)
        let silence = app.buttons["server-setting-stall_after_min"]
        XCTAssertTrue(silence.waitForExistence(timeout: 20), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "server-settings-groups-live"
        shot.lifetime = .keepAlways
        add(shot)
        silence.tap()
        let input = app.textFields["server-setting-value"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "11")
        app.buttons["server-setting-save"].tap()
        XCTAssertTrue(silence.waitForExistence(timeout: 10))
        XCTAssertTrue(silence.staticTexts["11 мин"].exists, app.debugDescription)
        silence.tap()
        app.buttons["server-setting-reset"].tap()
        app.buttons["Сбросить"].tap()
        XCTAssertTrue(silence.waitForExistence(timeout: 10))
        XCTAssertTrue(silence.staticTexts["10 мин"].exists)
        let summary = app.buttons["server-setting-slot_stop_summary"]
        for _ in 0..<8 {
            if summary.exists && summary.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(summary.exists)
        summary.tap()
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.buttons["server-setting-save"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.staticTexts["Выключено"].exists)
        summary.tap()
        app.buttons["server-setting-reset"].tap()
        app.buttons["Сбросить"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.staticTexts["Включено"].exists)
        let history = app.buttons["История изменений"]
        for _ in 0..<12 {
            if history.exists && history.isHittable { break }
            app.swipeUp()
        }
        history.tap()
        XCTAssertTrue(app.staticTexts["Из настроек iPhone"].firstMatch.waitForExistence(timeout: 10))
        let logShot = XCTAttachment(screenshot: app.screenshot())
        logShot.name = "server-settings-history-live"
        logShot.lifetime = .keepAlways
        add(logShot)

    }
}
