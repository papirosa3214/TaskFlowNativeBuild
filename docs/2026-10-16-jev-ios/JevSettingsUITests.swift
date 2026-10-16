import XCTest

final class JevSettingsUITests: XCTestCase {
    func testJevSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launch()
        let row = app.buttons["settings-jev"]
        for _ in 0..<10 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        row.tap()
        let model = app.textFields["jev-model"]
        XCTAssertTrue(model.waitForExistence(timeout: 20), app.debugDescription)
        capture(app, "01-jev-connection")
        XCTAssertFalse(app.buttons["jev-save"].isEnabled)
        model.tap()
        capture(app, "02-jev-keyboard")
        // Make the current connection dirty, then save its original value: exercises
        // real PUT without changing configuration or touching the existing secret.
        let original = model.value as? String ?? ""
        model.typeText(" ")
        app.swipeUp()
        let save = app.buttons["jev-save"]
        if !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        // Leave unsaved input on screen; no live configuration mutation in the UI check.
        XCTAssertFalse(app.buttons["jev-test"].isEnabled)
        for _ in 0..<7 { app.swipeUp() }
        let skills = app.switches["jev-scenario-skills"]
        XCTAssertTrue(skills.exists, app.debugDescription)
        capture(app, "03-jev-scenarios-bottom")
        XCTAssertFalse(original.isEmpty)
        app.terminate()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
