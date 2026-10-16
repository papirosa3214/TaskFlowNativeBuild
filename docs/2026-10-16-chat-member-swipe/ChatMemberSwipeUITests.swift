import XCTest
final class ChatMemberSwipeUITests: XCTestCase {
    func testMemberUsesBrandedDeleteSwipe() {
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
        member.swipeRight()
        let remove = app.buttons["chat.member.remove.role_researcher"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(remove.isHittable)
        XCTAssertEqual(remove.label, "Удалить из чата")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "member-delete-swipe"; shot.lifetime = .keepAlways; add(shot)
        // Не нажимаем удаление: проверяем оформление и раскрытие на локальном preview.
    }
}
