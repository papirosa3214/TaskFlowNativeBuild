import XCTest

final class StructuredRoleOutputPreviewUITests: XCTestCase {
    func testStructuredJSONPreviewRendersChatBlocks() {
        continueAfterFailure = false
        let app = makePreview(invalid: false)
        XCTAssertTrue(app.staticTexts["Проверка результата"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Промежуточный отчёт"].exists, app.debugDescription)
        let firstFrame = XCTAttachment(screenshot: app.screenshot())
        firstFrame.name = "structured-output-top"
        firstFrame.lifetime = .keepAlways
        add(firstFrame)

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Сверка этапов"].waitForExistence(timeout: 5), app.debugDescription)
        let tableFrame = XCTAttachment(screenshot: app.screenshot())
        tableFrame.name = "structured-output-table"
        tableFrame.lifetime = .keepAlways
        add(tableFrame)

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Передача результата"].waitForExistence(timeout: 5), app.debugDescription)
        let lastFrame = XCTAttachment(screenshot: app.screenshot())
        lastFrame.name = "structured-output-bottom"
        lastFrame.lifetime = .keepAlways
        add(lastFrame)
    }

    func testMalformedStructuredJSONRemainsVisibleAsAnError() {
        continueAfterFailure = false
        let app = makePreview(invalid: true)
        XCTAssertTrue(app.staticTexts["JSON не удалось разобрать"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["chat.structured-output.raw-error"].exists, app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "structured-output-invalid"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func makePreview(invalid: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_STRUCTURED_OUTPUT_PREVIEW"] = "1"
        if invalid { app.launchEnvironment["TASKFLOW_STRUCTURED_OUTPUT_INVALID_PREVIEW"] = "1" }
        app.launchArguments = ["-hints.enabled", "NO"]
        app.launch()
        return app
    }
}
