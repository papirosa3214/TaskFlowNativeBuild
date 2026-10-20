import XCTest

/// ВРЕМЕННЫЙ тест карточки 19f57bc9 (LOCK-IOS-ROLE-REPLY-RENDER): один и тот
/// же ответ роли — таблица и график — в пяти местах приложения. Данные живые:
/// тот же конверт стоит в комментарии карточки, в результате моего шага
/// плана, в итоге задачи и в чате по задаче. Тест только проверяет, что он
/// нарисован одинаково, и снимает кадры. Удаляется после приёмки.
final class RoleReplyRenderUITests: XCTestCase {

    private static let taskID = "19f57bc9-d82a-4b26-a8d0-eff0b9c395b1"
    /// Начало проверочного образца: одинаково во всех пяти местах.
    private static let marker = "Проверочный образец ответа роли"
    private static let stepTitle = "Доработка 1: Выполненный результат задачи"

    private var shotIndex = 0

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = route
        app.launch()
        return app
    }

    /// Кадр в отчёт и отдельным файлом: путь печатается в лог прогона.
    private func shot(_ app: XCUIApplication, _ name: String) {
        shotIndex += 1
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("role-reply-\(shotIndex)-\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
        NSLog("ROLE_REPLY_SHOT %@", url.path)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForCard(_ app: XCUIApplication) {
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "iOS: один рендер")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 60), "Карточка задачи не открылась")
    }

    /// Заголовок сворачиваемой секции карточки — кнопка, не текстовый элемент.
    @discardableResult
    private func openSection(_ app: XCUIApplication, _ title: String) -> Bool {
        let header = app.buttons[title]
        var tries = 0
        while tries < 30 {
            if header.exists, header.isHittable { header.tap(); return true }
            app.swipeUp()
            tries += 1
        }
        return false
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication, limit: Int = 30) -> Bool {
        var tries = 0
        while tries < limit {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
            tries += 1
        }
        return element.exists
    }

    private func markerText(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Self.marker)).firstMatch
    }

    /// Ответ нарисован общим рендером: блоки присутствуют, сырой разметки нет.
    private func assertRendered(_ app: XCUIApplication, _ place: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let all = app.descendants(matching: .any)
        for raw in ["```tf-json", "| Проверка |", "**Проверочный"] {
            XCTAssertFalse(all.matching(NSPredicate(format: "label CONTAINS %@", raw)).firstMatch.exists,
                           "\(place): видна сырая разметка ответа роли «\(raw)»", file: file, line: line)
        }
        XCTAssertTrue(all.matching(identifier: "chat.structured-output.table").firstMatch.exists,
                      "\(place): таблицы ответа роли нет", file: file, line: line)
        XCTAssertTrue(all.matching(identifier: "chat.structured-output.chart").firstMatch.exists,
                      "\(place): графика ответа роли нет", file: file, line: line)
    }

    /// Комментарий карточки, результат шага плана, итог задачи — один ответ роли.
    func testSameRoleReplyInCardPlaces() {
        let app = launch("task:\(Self.taskID)")
        waitForCard(app)

        // 1. Комментарий карточки.
        XCTAssertTrue(openSection(app, "Лента активности"), "Нет секции «Лента активности»")
        let comment = markerText(app)
        XCTAssertTrue(scrollTo(comment, app), "Проверочный комментарий не найден в ленте карточки")
        assertRendered(app, "комментарий карточки")
        shot(app, "comment")

        // 2. Результат шага плана: строка раскрывается по тапу.
        XCTAssertTrue(openSection(app, "Подзадачи"), "Нет секции «Подзадачи»")
        let step = app.staticTexts[Self.stepTitle]
        XCTAssertTrue(scrollTo(step, app), "Шаг «\(Self.stepTitle)» не найден")
        step.tap()
        let inStep = markerText(app)
        XCTAssertTrue(inStep.waitForExistence(timeout: 15), "Результат шага не раскрылся")
        _ = scrollTo(inStep, app)
        assertRendered(app, "результат шага плана")
        shot(app, "step-result")

        // 3. Итог задачи: тот же результат открывается шторкой.
        let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "закрыть")).firstMatch
        if close.exists { close.tap() }
        XCTAssertTrue(openSection(app, "Итог"), "Нет секции «Итог»")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.stepTitle)).firstMatch
        let rowText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Self.stepTitle)).firstMatch
        if scrollTo(row.exists ? row : rowText, app) {
            (row.exists ? row : rowText).tap()
            let inOutcome = markerText(app)
            XCTAssertTrue(inOutcome.waitForExistence(timeout: 15), "Итог задачи не открылся")
            _ = scrollTo(inOutcome, app)
            assertRendered(app, "итог задачи")
            shot(app, "task-outcome")
        } else {
            XCTFail("В секции «Итог» нет строки моего шага")
        }
    }

    /// Чат по задаче — тот же ответ роли в переписке ролей.
    func testSameRoleReplyInTaskChat() {
        let app = launch("task:\(Self.taskID)")
        waitForCard(app)

        guard openSection(app, "Чат по задаче") else {
            return XCTFail("У карточки нет чата — ответ роли в чате показать негде")
        }
        let chatRow = app.staticTexts.firstMatch
        var tries = 0
        while tries < 10, !chatRow.isHittable {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(chatRow.exists && chatRow.isHittable, "В секции «Чат по задаче» нет переписки")
        chatRow.tap()

        let reply = markerText(app)
        XCTAssertTrue(scrollTo(reply, app), "Ответ роли в чате по задаче не найден")
        assertRendered(app, "чат по задаче (лента роли)")
        shot(app, "task-chat")
    }
}
