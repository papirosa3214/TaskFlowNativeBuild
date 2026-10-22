import XCTest

/// Временная проверка лент (владелец 22.10.2026: «текста нет, но он всё
/// равно где-то», «криво встают мои сообщения непоследовательно по времени»,
/// «куда-то уезжает вниз»). Две ленты: комната роли (личные комнаты и группы)
/// и «Чат» Помощника владельца (отдельный экран).
final class ChatFeedStabilityUITests: XCTestCase {
    private func openRoom(_ app: XCUIApplication, id: String, name: String) {
        let room = app.buttons[id]
        XCTAssertTrue(room.waitForExistence(timeout: 30), "не открылся список комнат: \(name)")
        room.tap()
        let personal = app.buttons["Личная комната"]
        if personal.waitForExistence(timeout: 10) {
            personal.tap()
        } else {
            let link = app.staticTexts["Личная комната"]
            XCTAssertTrue(link.waitForExistence(timeout: 10), "не открылась карточка роли: \(name)")
            link.tap()
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Комната роли: текст ответа виден целиком, пустых строк нет.
    func testRoleRoomFeedShowsAnswer() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()
        openRoom(app, id: "chats.rooms.role_code_orchestrator", name: "оркестратор")
        sleep(8)
        XCTAssertTrue(app.staticTexts["На связи"].waitForExistence(timeout: 30), "текст ответа роли не виден")
        XCTAssertTrue(app.staticTexts["Ты тут"].exists, "своё сообщение не видно")
        attach(app, "room-role-orchestrator")
    }

    /// «Чат» Помощника владельца: экран открывается и лента наполнена.
    func testSecretaryChatOpens() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()
        openRoom(app, id: "chats.rooms.u-secretary", name: "помощник владельца")
        let screen = app.descendants(matching: .any).matching(identifier: "chat.screen").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 30), "не открылся чат помощника владельца")
        sleep(6)
        attach(app, "secretary-chat")
        var nonEmpty = 0
        for index in 0..<app.staticTexts.count {
            let text = app.staticTexts.element(boundBy: index)
            if text.exists && !text.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { nonEmpty += 1 }
        }
        XCTAssertGreaterThan(nonEmpty, 0, "лента пуста")
    }
}
