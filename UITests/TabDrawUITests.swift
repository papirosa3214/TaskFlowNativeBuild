import XCTest

final class TabDrawUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTabContoursInBothThemes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab.directory"].waitForExistence(timeout: 40))
        for dark in [false, true] {
            app.buttons["tab.directory"].tap()
            let settings = app.staticTexts["Настройки"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            settings.tap()
            let toggle = app.switches["settings.appearance"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 15))
            if toggle.value as? String != (dark ? "1" : "0") { toggle.tap() }
            app.buttons["BackButton"].tap()
            let theme = dark ? "dark" : "light"
            for tab in ["tab.projects", "tab.upcoming", "tab.chat", "tab.directory"] {
                XCTAssertTrue(app.buttons[tab].exists)
                app.buttons[tab].tap()
                capture(app, "\(theme)-\(tab)-drawing")
                // Даём контуру завершиться для итогового кадра; навигация только по identifier.
                Thread.sleep(forTimeInterval: 1.6)
                capture(app, "\(theme)-\(tab)-complete")
                XCTAssertTrue(app.buttons["tab.add"].exists)
            }
        }
    }
}
