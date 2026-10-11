import XCTest
final class PromptButtonOrderUITests: XCTestCase {
    func testButtonOrder() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_COMPOSER_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_PROMPT_BOX_PREVIEW"] = "1"
        app.launchArguments += ["-chat.experimentalPromptBox", "YES"]
        app.launch()
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        let clip = element("chat.attachment")
        XCTAssertTrue(clip.waitForExistence(timeout: 15))
        let mention = element("chat.mention")
        XCTAssertTrue(mention.waitForExistence(timeout: 5))
        let mode = element("chat.mode"), mic = element("chat.voice")
        XCTAssertLessThan(clip.frame.midX, mention.frame.midX)
        XCTAssertLessThan(mention.frame.midX, mode.frame.midX)
        XCTAssertLessThan(mode.frame.midX, mic.frame.midX)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "button-order"; shot.lifetime = .keepAlways; add(shot)
    }
}
