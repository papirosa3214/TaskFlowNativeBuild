import XCTest

final class AppAppearanceUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Обзор"].waitForExistence(timeout: 40))
        app.buttons["Обзор"].tap()
        let settings = app.staticTexts["Настройки"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.switches["settings.appearance"].waitForExistence(timeout: 15))
    }

    private func setDark(_ enabled: Bool, in app: XCUIApplication) {
        let toggle = app.switches["settings.appearance"]
        let expected = enabled ? "1" : "0"
        if toggle.value as? String != expected { toggle.tap() }
        let changed = NSPredicate(format: "value == %@", expected)
        expectation(for: changed, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }

    func testOriginalSwitchChangesThemeAndPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openSettings(app)
        setDark(false, in: app)
        capture(app, "light-settings-toggle")
        app.terminate()
        app.launch()
        openSettings(app)
        XCTAssertEqual(app.switches["settings.appearance"].value as? String, "0")
        capture(app, "light-settings-toggle-after-relaunch")
        setDark(true, in: app)
        capture(app, "dark-settings-toggle")
        app.buttons["Обзор"].tap()
        capture(app, "dark-overview-toggle")
    }
}
