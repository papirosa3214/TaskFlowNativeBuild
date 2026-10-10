import XCTest

/// ВРЕМЕННЫЙ тест (владелец 11.10.2026). Требование: в экспериментальном
/// поле ввода ПОСЛЕ отправки («молнии») стоит серенькая кнопка-собачка «@»;
/// по тапу открывается список ролей чата, а выбор подставляет «@Имя » в
/// текст и оставляет фокус в поле. После сверки кадров — удалить.
final class PromptBoxMentionUITests: XCTestCase {

    /// SwiftUI отдаёт идентификатор то как image, то как button — ищем по любому типу.
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testMentionButtonOpensRolesAndInserts() {
        let app = XCUIApplication()
        // Экспериментальное поле включается флагом `chat.experimentalPromptBox`
        // в UserDefaults (@AppStorage). Осталось от прошлых прогонов — не
        // повод полагаться: выставляем аргументом запуска, тогда проверка не
        // зависит ни от истории симулятора, ни от тумблера в меню.
        app.launchArguments += ["-chat.experimentalPromptBox", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Чат"].waitForExistence(timeout: 30), "нет вкладки чата")
        app.buttons["Чат"].tap()

        // Групповой чат: в 1:1 собачки нет — там адресат и так один.
        // Отладочного маршрута на конкретный чат нет («chat» открывает лишь
        // вкладку), поэтому ищем по названию. Строка списка — это staticText
        // с заголовком рядом с превью, а не button и не cell: находим текст и
        // тапаем по нему.
        let groupChat = app.staticTexts["Общий чат"]
        if groupChat.waitForExistence(timeout: 15) {
            groupChat.tap()
        } else {
            let firstChat = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Секретарь' OR label CONTAINS[c] 'Разраб' OR label CONTAINS[c] 'Архитектор'")
            ).firstMatch
            if !firstChat.waitForExistence(timeout: 10) {
                attach(app, name: "chats-empty")
                XCTFail("список чатов не догрузился — смотри кадр chats-empty")
            }
            firstChat.tap()
        }

        let field = element(app, "chat.message")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "нет поля ввода")
        field.tap()
        sleep(1)
        attach(app, name: "chat-open")

        // 1. Кнопка-собачка стоит ПОСЛЕ отправки-«молнии» — владелец 11.10:
        //    «после молнии надо ставить, чтобы он тоже был таким вот сереньким».
        let mention = element(app, "chat.mention")
        let send = element(app, "chat.send")
        XCTAssertTrue(mention.waitForExistence(timeout: 10), "кнопки «@» нет в экспериментальном поле")
        let mic = element(app, "chat.voice")
        let anchor = send.exists ? send : mic
        XCTAssertTrue(anchor.exists, "нет ни отправки, ни микрофона в поле")
        let mentionFrame = mention.frame
        let anchorFrame = anchor.frame
        print("MARK mention=\(Int(mentionFrame.minY)) anchor=\(Int(anchorFrame.minY)) mentionAfter=\(mentionFrame.minX >= anchorFrame.maxX)")
        XCTAssertGreaterThanOrEqual(mentionFrame.minX, anchorFrame.maxX,
                                    "собачка должна быть ПОСЛЕ отправки, а не у микрофона")
        attach(app, name: "mention-button")

        // 2. По тапу открывается список ролей.
        mention.tap()
        sleep(2)
        attach(app, name: "mention-menu-open")

        // 3. Выбор роли подставляет «@Имя » в текст.
        let menuItem = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Разработчик' OR label CONTAINS[c] 'Исследователь' OR label CONTAINS[c] 'Аналитик' OR label CONTAINS[c] 'Секретарь' OR label CONTAINS[c] 'Критик'")
        ).firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 10), "список ролей не открылся или пуст")

        let roleLabel = menuItem.label.replacingOccurrences(of: "at, ", with: "")
        menuItem.tap()
        sleep(2)
        attach(app, name: "mention-inserted")

        let typed = (field.value as? String) ?? ""
        print("MARK role=\(roleLabel) field=\(typed)")
        XCTAssertTrue(typed.contains("@"), "в поле нет упоминания: «\(typed)»")
        XCTAssertTrue(typed.hasSuffix(" ") || typed.contains("@\(roleLabel)"),
                      "упоминание вставлено неверно: «\(typed)»")
    }
}