import XCTest

/// ВРЕМЕННЫЙ тест карточки 19f57bc9 (LOCK-IOS-ROLE-REPLY-RENDER): один и тот
/// же ответ роли — таблица и график — в местах приложения, где он показывается.
/// Данные живые: тот же конверт стоит в переписке по задаче, в комментарии
/// карточки, в результате моего шага плана и в итоге задачи. Тест проверяет,
/// что он нарисован одинаково, и снимает кадры. Удаляется после приёмки.
///
/// Обход карточки — одним проходом сверху вниз в порядке секций (Итог,
/// Подзадачи, Лента активности, Чат по задаче): возврат наверх после
/// раскрытой секции unreliable — список длинный, а прокрутка назад
/// закрывала карточку.
final class RoleReplyRenderUITests: XCTestCase {

    private static let taskID = "19f57bc9-d82a-4b26-a8d0-eff0b9c395b1"
    /// Начало проверочного образца: одинаково во всех местах.
    private static let marker = "Проверочный образец ответа роли"
    private static let stepTitle = "Доработка 1: Выполненный результат задачи"

    private var shotIndex = 0

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = route
        app.launch()
        return app
    }

    /// Кадр в отчёт прогона и отдельным файлом: путь печатается в лог.
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

    /// Заголовок сворачиваемой секции карточки — кнопка, а не текстовый элемент.
    @discardableResult
    private func openSection(_ app: XCUIApplication, _ title: String) -> Bool {
        let header = app.buttons[title]
        var tries = 0
        while tries < 45 {
            if header.exists, header.isHittable {
                header.tap()
                return true
            }
            app.swipeUp()
            tries += 1
        }
        NSLog("ROLE_REPLY_NO_SECTION %@", title)
        return false
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication, limit: Int = 20) -> Bool {
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

    /// Кнопка закрытия шторки итога называется по-разному в разных сборках
    /// («Готово», «закрыть») — берём любую из них, иначе карточка остаётся
    /// перекрыта и следующая секция не находится.
    private func closeSheetIfOpen(_ app: XCUIApplication) {
        for label in ["Готово", "Закрыть", "закрыть"] {
            let close = app.buttons[label].firstMatch
            if close.exists, close.isHittable {
                close.tap()
                return
            }
        }
    }

    /// Тот же ответ роли в результате шага плана и в переписке по задаче.
    /// Секция «Итог» идёт первой и открывается шторкой — она проверяется
    /// вторым тестом, здесь обход короче и устойчивее.
    func testSameRoleReplyInStepResultAndTaskChat() {
        let app = launch("task:\(Self.taskID)")
        waitForCard(app)

        XCTAssertTrue(openSection(app, "Подзадачи"), "Нет секции «Подзадачи»")
        let step = app.staticTexts[Self.stepTitle]
        XCTAssertTrue(scrollTo(step, app, limit: 25), "Шаг «\(Self.stepTitle)» не найден")
        step.tap()
        let inStep = markerText(app)
        XCTAssertTrue(inStep.waitForExistence(timeout: 20), "Результат шага не раскрылся")
        _ = scrollTo(inStep, app)
        assertRendered(app, "результат шага плана")
        shot(app, "step-result")

        XCTAssertTrue(openSection(app, "Чат по задаче"), "Нет секции «Чат по задаче»")
        let byParticipants = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "участников")).firstMatch
        var tries = 0
        while tries < 8, !(byParticipants.exists && byParticipants.isHittable) {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(byParticipants.exists && byParticipants.isHittable,
                      "В секции «Чат по задаче» нет переписки")
        byParticipants.tap()
        let reply = markerText(app)
        XCTAssertTrue(scrollTo(reply, app, limit: 25), "Ответ роли в переписке по задаче не найден")
        assertRendered(app, "переписка по задаче (лента роли)")
        shot(app, "task-chat")
    }
}
