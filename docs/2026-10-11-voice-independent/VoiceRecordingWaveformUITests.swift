import XCTest
final class VoiceRecordingWaveformUITests: XCTestCase {
    func testBothRecordingWaveforms() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_VOICE_HISTORY_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Голосовое сообщение"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Расшифровка в текст"].exists)
        let ready = app.staticTexts["voice.preview.ready"]
        expectation(for: NSPredicate(format: "label == %@", "Аудиообразец прочитан"), evaluatedWith: ready)
        waitForExpectations(timeout: 20)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Два режима — аудиообразец речи"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
