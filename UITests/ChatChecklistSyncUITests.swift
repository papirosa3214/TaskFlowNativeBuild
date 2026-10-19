import XCTest

/// Временный тест LOCK-CHAT-CHECKLIST-SYNC-20261019: отметка пункта
/// checklist-виджета уходит на сервер и переживает перезапуск приложения.
/// Удалить после приёмки.
final class ChatChecklistSyncUITests: XCTestCase {
    private let chatTitle = ProcessInfo.processInfo.environment["TASKFLOW_CHECKLIST_CHAT"] ?? "Разраб"
    private let itemLabel = ProcessInfo.processInfo.environment["TASKFLOW_CHECKLIST_ITEM"] ?? "Оплатить связь"

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()
        return app
    }

    /// Открыть чат по подписи строки и дождаться пункта чек-листа.
    private func openChecklist(in app: XCUIApplication) -> XCUIElement {
        let row = app.staticTexts[chatTitle].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "не нашёл чат \(chatTitle)")
        row.tap()
        // Чат открывается не сразу: сначала «Загрузка чата», потом лента.
        // Пункт ищем с прокруткой — виджет может быть ниже видимой части.
        let item = app.buttons[itemLabel].firstMatch
        var found = waitValue("Отмечен", of: item) ? true : item.waitForExistence(timeout: 20)
        for _ in 0..<6 where !found {
            app.swipeUp()
            found = item.waitForExistence(timeout: 5)
        }
        let opened = XCTAttachment(screenshot: app.screenshot())
        opened.name = "chat-opened"
        opened.lifetime = .keepAlways
        add(opened)
        XCTAssertTrue(found, "не нашёл пункт \(itemLabel)")
        return item
    }

    func testChecklistMarkReachesServerAndSurvivesRelaunch() {
        let app = launch()
        let item = openChecklist(in: app)
        item.tap()
        XCTAssertTrue(waitValue("Отмечен", of: item), "отметка не показалась сразу после нажатия")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "checklist-marked"
        shot.lifetime = .keepAlways
        add(shot)

        // Перезапуск приложения: состояние должно прийти с сервера, а не из
        // памяти клиента.
        app.terminate()
        let again = launch()
        let reopened = openChecklist(in: again)
        XCTAssertTrue(waitValue("Отмечен", of: reopened),
                      "после перезапуска пункт снова не отмечен — состояние не с сервера")
    }

    private func waitValue(_ value: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 15) == .completed
    }
}
