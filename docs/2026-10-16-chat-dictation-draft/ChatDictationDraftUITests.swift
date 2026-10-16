import XCTest
final class ChatDictationDraftUITests: XCTestCase {
    private func launch(fail: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_PROMPT_BOX_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_DICTATION_PREVIEW"] = "1"
        if fail { app.launchEnvironment["TASKFLOW_DICTATION_PREVIEW_FAIL"] = "1" }
        app.launchArguments = ["-hints.enabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.mention"].waitForExistence(timeout: 15))
        app.buttons["chat.mention"].tap(); app.buttons["Архитектор"].tap()
        return app
    }
    private func record(_ app: XCUIApplication) {
        let mic = app.buttons["chat.voice"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5)); XCTAssertTrue(mic.isHittable)
        mic.tap()
        let stop = app.buttons["Остановить запись"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.tap()
    }
    func testDictationAfterMentionRemainsEditableAndDoesNotSend() {
        let app = launch()
        var field = app.descendants(matching: .any)["chat.message"].firstMatch
        field.tap(); field.typeText("manual ")
        record(app)
        field = app.descendants(matching: .any)["chat.message"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue((field.value as? String)?.contains("@Архитектор") == true, String(describing: field.value))
        XCTAssertTrue((field.value as? String)?.contains("Проверка диктовки.") == true, String(describing: field.value))
        field.tap(); field.typeText(" edited")
        let edited = field.value as? String ?? ""
        XCTAssertTrue(edited.lowercased().contains("edited"), edited)
        XCTAssertFalse(app.staticTexts["chat.preview.sent-text"].exists)
        record(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let final = field.value as? String ?? ""
        XCTAssertTrue(final.contains("@Архитектор")); XCTAssertTrue(final.lowercased().contains("edited"), final)
        XCTAssertEqual(final.components(separatedBy: "Проверка диктовки.").count - 1, 2)
        XCTAssertTrue(app.buttons["chat.voice"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "editable-dictation-with-mention"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts["chat.preview.sent-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chat.preview.sent-text"].label, final)
    }
    func testFailedDictationKeepsExistingDraft() {
        let app = launch(fail: true)
        let field = app.descendants(matching: .any)["chat.message"].firstMatch
        field.tap(); field.typeText("keep")
        let original = field.value as? String
        record(app)
        XCTAssertTrue(app.staticTexts["chat.voice.transcription-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.voice.send"].isEnabled)
        app.buttons["chat.voice.discard"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, original)
        XCTAssertFalse(app.staticTexts["chat.preview.sent-text"].exists)
        XCTAssertTrue(app.buttons["chat.voice"].exists)
    }
}
