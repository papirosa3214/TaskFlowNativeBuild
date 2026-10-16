import XCTest
final class ChatMemberCompactUITests: XCTestCase {
    func testCompactMembersOnlyUseContextMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_MEMBER_SWIPE_PREVIEW"] = "1"
        app.launchArguments = ["-hints.enabled", "NO"]
        app.launch()
        let details = app.buttons["Чат: название и участники"]
        XCTAssertTrue(details.waitForExistence(timeout: 15)); details.tap()
        let member = app.cells.containing(.staticText, identifier: "Исследователь").firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThanOrEqual(member.frame.height, 62)
        member.swipeRight()
        XCTAssertFalse(app.buttons["chat.member.remove.role_researcher"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compact-members"; shot.lifetime = .keepAlways; add(shot)
        member.staticTexts["Исследователь"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Удалить из чата"].waitForExistence(timeout: 5), app.debugDescription)
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "member-context-delete"; menu.lifetime = .keepAlways; add(menu)
    }
}
