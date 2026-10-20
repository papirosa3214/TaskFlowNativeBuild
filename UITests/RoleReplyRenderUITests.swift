import XCTest

/// ВРЕМЕННЫЙ тест карточки 19f57bc9 (LOCK-IOS-ROLE-REPLY-RENDER): кадры,
/// что ответ роли рисуется одним рендером в чате, в комментарии карточки,
/// в результате шага и в итоге задачи. Удаляется после съёмки.
final class RoleReplyRenderUITests: XCTestCase {

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Карточка открывается не сразу: сначала вход по домашней сети, потом
    /// загрузка. Ждём первое известное слово карточки — дальше список готов.
    private func waitForTaskCard(_ app: XCUIApplication) {
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "iOS: один рендер")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 40), "Карточка задачи не открылась")
    }

    /// Прокрутка до названия секции карточки и тап по нему.
    @discardableResult
    private func openSection(_ app: XCUIApplication, _ title: String) -> Bool {
        // Заголовок сворачиваемой секции — кнопка, не текстовый элемент.
        let header = app.buttons[title]
        var tries = 0
        while tries < 25 {
            if header.exists, header.isHittable { header.tap(); return true }
            app.swipeUp()
            tries += 1
        }
        return false
    }

    /// Прокрутка до текста, который ищем на экране.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication, limit: Int = 25) -> Bool {
        var tries = 0
        while tries < limit {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
            tries += 1
        }
        return element.exists
    }

    /// 1. Чат: ответ роли рисуется тем же рендером.
    func testRoleReplyInRoleChat() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()

        let assistant = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Помощник владельца")).firstMatch
        XCTAssertTrue(assistant.waitForExistence(timeout: 40), "Список чатов не открылся")
        assistant.tap()

        // Ответ роли в ленте: ждём кусок текста, который пишет только роль.
        var tries = 0
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Проверка")).firstMatch
        while tries < 20 {
            if reply.exists, reply.isHittable { break }
            app.swipeUp()
            tries += 1
        }
        shot(app, "01-chat-role-reply")
    }

    /// 2. Комментарий карточки: тот же ответ роли в ленте карточки.
    func testRoleReplyInTaskComment() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:19f57bc9-d82a-4b26-a8d0-eff0b9c395b1"
        app.launch()
        waitForTaskCard(app)

        XCTAssertTrue(openSection(app, "Лента активности"), "Нет секции «Лента активности»")
        let marker = app.staticTexts["Проверочный образец: тот же ответ роли, что в чате, — в комментарии карточки."]
        XCTAssertTrue(scrollTo(marker, app), "Не нашли проверочный комментарий в ленте")
        shot(app, "02-task-comment-role-reply")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "chat.structured-output.table").firstMatch.exists,
            "Комментарий нарисован не тем же рендером: таблицы нет")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "chat.structured-output.chart").firstMatch.exists,
            "Комментарий нарисован не тем же рендером: графика нет")
    }

    /// 3 и 4. Результат шага и итог задачи — один и тот же текст роли в двух
    /// местах карточки аудита (шаг «Итоговая проверка результата»).
    func testRoleReplyInStepResultAndTaskOutcome() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:65fb1128-e2ec-465d-a0c6-9a2e4d5fefe3"
        app.launch()
        let auditTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Аудит дизайн-системы")).firstMatch
        XCTAssertTrue(auditTitle.waitForExistence(timeout: 40), "Карточка аудита не открылась")

        XCTAssertTrue(openSection(app, "Подзадачи"), "Нет секции «Подзадачи»")
        let step = app.staticTexts["Итоговая проверка результата"]
        guard scrollTo(step, app) else { return XCTFail("Не нашли шаг в карточке") }
        step.tap()

        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Три блокирующих дефекта")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 10), "Итог шага не показан")
        shot(app, "03-step-result-role-reply")

        XCTAssertTrue(openSection(app, "Итог"), "Нет секции «Итог»")
        let same = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Три блокирующих дефекта")).firstMatch
        _ = scrollTo(same, app)
        shot(app, "04-task-outcome-role-reply")
        XCTAssertTrue(same.exists, "Итог задачи не показывает тот же текст роли")
    }
}
