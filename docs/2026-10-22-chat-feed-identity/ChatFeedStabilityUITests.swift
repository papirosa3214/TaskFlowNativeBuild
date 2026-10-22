import XCTest

/// Временная проверка ленты роли (владелец 22.10.2026: «текста нет, но он
/// всё равно где-то», сообщения встают криво по времени). Личный чат с
/// оркестратором: там больше всего строк от одной роли на один ответ
/// (в живой базе — шесть строк от роли на один вопрос).
///
/// Проверяем главное: ТЕКСТ ответа виден в ленте и не путается с другими
/// строками. Идентификатор ScrollView в дерево XCUITest не попадает, поэтому
/// ищем по самому тексту ответа.
final class ChatFeedStabilityUITests: XCTestCase {
    func testRoleChatFeedShowsEveryBubble() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()

        let room = app.buttons["chats.rooms.role_code_orchestrator"]
        XCTAssertTrue(room.waitForExistence(timeout: 30), "не открылся список комнат")
        room.tap()

        let personal = app.buttons["Личная комната"]
        if personal.waitForExistence(timeout: 10) {
            personal.tap()
        } else {
            let link = app.staticTexts["Личная комната"]
            XCTAssertTrue(link.waitForExistence(timeout: 10), "не открылась карточка роли")
            link.tap()
        }

        // Ответ оркестратора обязан быть виден целиком.
        let answer = app.staticTexts["На связи"]
        XCTAssertTrue(answer.waitForExistence(timeout: 30), "текст ответа роли не виден в ленте")
        // Своё сообщение — тоже.
        XCTAssertTrue(app.staticTexts["Ты тут"].exists, "своё сообщение не видно")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "chat-feed-orchestrator"
        shot.lifetime = .keepAlways
        add(shot)

        // Пустых видимых строк быть не должно — «текста нет, но он где-то».
        var empty = 0
        for index in 0..<app.staticTexts.count {
            let text = app.staticTexts.element(boundBy: index)
            if text.exists && text.label.isEmpty { empty += 1 }
        }
        XCTAssertEqual(empty, 0, "в ленте есть пустые строки")
    }
}
