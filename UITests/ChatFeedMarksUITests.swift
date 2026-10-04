import XCTest

/// Временный приёмочный сценарий LOCK-CHAT-FEED-MARKS-20261003: кнопка «вниз»
/// и плашки дат в ленте переписки. Ходит в живой сервер на .110 (вход в
/// приложение — штатный LAN-логин из домашней сети), ничего не создаёт и не
/// отправляет: только смотрит и катает ленту вверх-вниз.
final class ChatFeedMarksUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Открыть первый чат с ролью (не блок «Секретарь» — он идёт первым и сам
    /// по себе тоже комната, но строки у него другие).
    @discardableResult
    private func openFirstRoleChat(_ app: XCUIApplication) -> XCUIElement {
        let tab = app.buttons["Чат"]
        XCTAssertTrue(tab.waitForExistence(timeout: 40), "нет вкладки «Чат»")
        tab.tap()

        let secretary = app.staticTexts["Секретарь"]
        XCTAssertTrue(secretary.waitForExistence(timeout: 30), "список чатов не открылся")
        let secretRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Секретарь")).firstMatch
        XCTAssertTrue(secretRow.waitForExistence(timeout: 5), "нет строки «Секретарь»")

        let roles = app.buttons.allElementsBoundByIndex.filter { button in
            button.exists && !button.label.contains("Секретарь")
                && button.frame.minY > secretRow.frame.maxY
        }
        XCTAssertFalse(roles.isEmpty, "в списке нет ни одного чата с ролью")
        guard let row = roles.first else { return app.buttons["Чат"] }
        row.tap()
        return row
    }

    func testRoomDayPillsAndScrollDownButton() {
        let app = XCUIApplication()
        app.launch()
        openFirstRoleChat(app)

        // Плашка внизу ленты — дата последнего сообщения.
        let endPill = app.staticTexts["chat.day.end"]
        XCTAssertTrue(endPill.waitForExistence(timeout: 30), "нет закрывающей плашки даты")
        print("[chat-marks] закрывающая плашка: \(endPill.label)")

        // Плашка смены дня перед первым сообщением — всегда хотя бы одна.
        let dayPills = app.staticTexts.matching(identifier: "chat.day-divider")
        print("[chat-marks] плашек дня в дереве: \(dayPills.count)")

        capture(app, "room-bottom-with-end-date")

        // Уехали вверх — кнопка «вниз» должна появиться.
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 15), "нет ленты сообщений")
        let down = app.buttons["chat.scroll-to-bottom"]
        if !down.exists {
            feed.swipeDown()
        }
        XCTAssertTrue(down.waitForExistence(timeout: 10), "кнопка «вниз» не появилась после прокрутки вверх")
        capture(app, "room-scrolled-up-down-button")

        // Плашки дня в прокрученной ленте — снимаем то, что видно.
        print("[chat-marks] видимых плашек дня: \(app.staticTexts.matching(identifier: "chat.day-divider").count)")

        // Нажали — вернулись к последнему сообщению, кнопка исчезла.
        down.tap()
        XCTAssertTrue(down.waitForNonExistence(timeout: 10), "кнопка «вниз» не исчезла после нажатия")
        XCTAssertTrue(app.staticTexts["chat.day.end"].exists, "после возврата вниз пропала закрывающая плашка")
        capture(app, "room-back-at-bottom-after-tap")
    }
}