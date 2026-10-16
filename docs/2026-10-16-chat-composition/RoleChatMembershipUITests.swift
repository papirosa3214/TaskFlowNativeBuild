import XCTest

/// Меняет состав только своего временного чата; сообщения ролям не отправляет.
final class RoleChatMembershipUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func assertMode(_ app: XCUIApplication, _ prefix: String) {
        let label = app.staticTexts["chat.details.addressing"]
        let match = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            label.exists && label.label.hasPrefix(prefix)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed)
    }
    func testSecretaryInvitationAndChatModeRoundTrip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hints.enabled", "NO"]
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()
        let menu = app.buttons["chats.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        app.buttons["Чат с участниками"].tap()
        let secretary = app.buttons["chat.create.member.secretary"]
        XCTAssertTrue(secretary.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["chat.create.member.designer"].exists)
        let title = "Проверка участников " + UUID().uuidString.prefix(8)
        app.textFields["Необязательно"].tap()
        app.textFields["Необязательно"].typeText(title)
        secretary.tap()
        app.buttons["chat.create.member.designer"].tap()
        shot(app, "01-secretary-selectable")
        app.buttons["Создать чат"].tap()
        let chat = app.staticTexts[title].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 20))
        chat.tap()
        let details = app.buttons["Чат: название и участники"]
        XCTAssertTrue(details.waitForExistence(timeout: 20))
        details.tap()
        assertMode(app, "Групповой чат")
        shot(app, "02-created-group")
        let assistant = app.staticTexts["Помощник владельца"].firstMatch
        XCTAssertTrue(assistant.waitForExistence(timeout: 5))
        assistant.press(forDuration: 1)
        app.buttons["Удалить из чата"].tap()
        assertMode(app, "Личный чат")
        shot(app, "03-removed-to-direct")
        app.buttons["chat.details.menu"].tap()
        app.buttons["Добавить участника"].tap()
        let invite = app.buttons["Помощник владельца"]
        XCTAssertTrue(invite.waitForExistence(timeout: 5))
        invite.tap()
        assertMode(app, "Групповой чат")
        shot(app, "04-secretary-invited-to-group")
        app.buttons["chat.details.menu"].tap()
        app.buttons["Удалить чат"].tap()
        let confirm = app.buttons["Удалить чат"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        shot(app, "05-test-chat-deleted")
    }
}
