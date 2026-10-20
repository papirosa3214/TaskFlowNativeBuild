import XCTest

/// ВРЕМЕННЫЙ тест карточки 19f57bc9 (доработка 1, проверка QA): один и тот
/// же ответ роли — таблица и график — в местах приложения, где он
/// показывается, и результат шага, который хранится обрамлённым конвертом.
///
/// Отличие от прежней версии теста: каждое место проверяется СВОИМ запуском
/// приложения (свежий экран карточки вместо длинного обхода одним проходом) и
/// график ищется по обоим идентификаторам — «chat.structured-output.chart»
/// (путь конверта) и «role.chart» (путь ```widget через RoleReplyMarkdown).
/// Прежний тест искал только первый идентификатор, поэтому в результате шага и
/// в переписке нарисованный правильно график не находился.
///
/// Удаляется после приёмки карточки.
final class RoleReplyRenderUITests: XCTestCase {

    private static let taskID = "19f57bc9-d82a-4b26-a8d0-eff0b9c395b1"

    /// Комментарий Максима в ленте карточки: путь конверта.
    private static let journalMarker = "Проверочный образец: тот же ответ роли"
    /// Сообщение разработчика в чате по задаче: путь ```widget.
    private static let chatMarker = "Проверочный образец ответа роли для кадров"
    private static let stepTitle = "Доработка 1: Выполненный результат задачи"

    private var shotIndex = 0

    // MARK: - Помощники

    private func launchCard() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:\(Self.taskID)"
        // Без этого симулятор восстанавливает шторку прошлой сессии поверх
        // отладочного перехода: прогон 20.10.2026 попал в карточку соседней
        // задачи («Web Desktop») и искал образец не там.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        // Карточка может открыться под липкой «Зависшие шаги» — снимаем её,
        // иначе секции под ней не находятся.
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 8) {
            let ok = alert.buttons["Понятно"]
            if ok.exists { ok.tap() }
        }
        // Ждём именно заголовок этой карточки и убеждаемся, что это верхний
        // экран: если открылась соседняя карточка, честно падаем с кадром.
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "iOS: один рендер")).firstMatch
        if !title.waitForExistence(timeout: 60) {
            shot(app, "card-not-opened")
            XCTFail("Карточка задачи не открылась")
            return app
        }
        let neighbour = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Web Desktop")).firstMatch
        if neighbour.exists, neighbour.isHittable {
            shot(app, "wrong-card")
            XCTFail("Открылась соседняя карточка «\(neighbour.label)», а не 19f57bc9")
            return app
        }
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        shotIndex += 1
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qa-19f57bc9-\(shotIndex)-\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
        NSLog("QA_ROLE_REPLY_SHOT %@", url.path)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Заголовок сворачиваемой секции карточки — это кнопка. Ищем её прокруткой
    /// сверху вниз; если не нашли, пишем в лог и возвращаем false.
    @discardableResult
    private func openSection(_ app: XCUIApplication, _ title: String) -> Bool {
        let header = app.buttons[title]
        var tries = 0
        while tries < 50 {
            if header.exists, header.isHittable {
                header.tap()
                return true
            }
            app.swipeUp()
            tries += 1
        }
        NSLog("QA_NO_SECTION %@ (прокруток: %d)", title, tries)
        return false
    }

    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication, limit: Int = 30) -> Bool {
        var tries = 0
        while tries < limit {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
            tries += 1
        }
        return element.exists
    }

    private func anyElement(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any)
    }

    /// График ответа роли: конверт рисует его с идентификатором
    /// «chat.structured-output.chart», блок ```widget — с «role.chart».
    private func chartExists(_ app: XCUIApplication) -> Bool {
        let all = anyElement(app)
        for id in ["chat.structured-output.chart", "role.chart"] {
            if all.matching(identifier: id).firstMatch.exists { return true }
        }
        return false
    }

    private func tableExists(_ app: XCUIApplication) -> Bool {
        let all = anyElement(app)
        if all.matching(identifier: "chat.structured-output.table").firstMatch.exists { return true }
        // У блока ```widget идентификатора нет — таблица ищется по содержимому.
        return all.matching(NSPredicate(format: "label CONTAINS %@", "RoleReplyChartTests")).firstMatch.exists
    }

    /// Сырой разметки быть не должно ни в одном из путей.
    private func assertNoRawMarkup(_ app: XCUIApplication, _ place: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let all = anyElement(app)
        for raw in ["```tf-json", "```widget", "\"schema_version\"", "| Проверка |", "**Проверочный"] {
            XCTAssertFalse(all.matching(NSPredicate(format: "label CONTAINS %@", raw)).firstMatch.exists,
                           "\(place): видна сырая разметка «\(raw)»", file: file, line: line)
        }
    }

    // MARK: - Место 1. Комментарий карточки (путь конверта)

    func testSampleReplyInCardJournal() {
        let app = launchCard()
        XCTAssertTrue(openSection(app, "Лента активности"), "Нет секции «Лента активности»")
        let sample = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Self.journalMarker)).firstMatch
        XCTAssertTrue(scrollTo(sample, app), "Проверочный комментарий в ленте карточки не найден")
        assertNoRawMarkup(app, "комментарий карточки")
        XCTAssertTrue(tableExists(app), "В комментарии карточки нет таблицы ответа роли")
        XCTAssertTrue(chartExists(app), "В комментарии карточки нет графика ответа роли")
        shot(app, "journal-comment")
    }

    // MARK: - Место 2. Переписка по задаче (путь ```widget)

    func testSampleReplyInTaskChat() {
        let app = launchCard()
        XCTAssertTrue(openSection(app, "Чат по задаче"), "Нет секции «Чат по задаче»")
        let conversation = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "участников")).firstMatch
        var tries = 0
        while tries < 12, !(conversation.exists && conversation.isHittable) {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(conversation.exists && conversation.isHittable, "В секции «Чат по задаче» нет переписки")
        conversation.tap()
        let sample = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Self.chatMarker)).firstMatch
        XCTAssertTrue(scrollTo(sample, app), "Ответ роли с образцом в переписке не найден")
        assertNoRawMarkup(app, "переписка по задаче")
        XCTAssertTrue(tableExists(app), "В переписке по задаче нет таблицы ответа роли")
        XCTAssertTrue(chartExists(app), "В переписке по задаче нет графика ответа роли")
        shot(app, "task-chat")
    }

    // MARK: - Место 3. Результат шага плана (путь ```widget)

    func testStepResultRendersBlocksNotRawJson() {
        let app = launchCard()
        XCTAssertTrue(openSection(app, "Подзадачи"), "Нет секции «Подзадачи»")
        let step = app.staticTexts[Self.stepTitle]
        XCTAssertTrue(scrollTo(step, app), "Шаг «\(Self.stepTitle)» не найден")
        step.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "График ответа роли")).firstMatch
        if !result.waitForExistence(timeout: 25) {
            let any = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "результат")).firstMatch
            _ = any.waitForExistence(timeout: 5)
        }
        assertNoRawMarkup(app, "результат шага плана")
        shot(app, "step-result")
    }
}
