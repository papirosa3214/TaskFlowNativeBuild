import XCTest

/// ВРЕМЕННЫЙ тест QA карточки 19f57bc9: один и тот же ответ роли в пяти
/// местах — чат, лента роли (тот же чат), комментарий карточки, результат
/// шага плана, итог задачи. Данные — фикстура 127.0.0.1:3320, в которой одна
/// и та же строка (жирный, заголовок, markdown-таблица, блок графика) отдана
/// во все пять мест. Кадры пишутся во временный каталог раннера.
final class RoleReplyRenderUITests: XCTestCase {

    private var shotIndex = 0

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3320"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = route
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        shotIndex += 1
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qa-shot-\(shotIndex)-\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
        NSLog("QA_SHOT %@", url.path)
    }

    /// Ответ нарисован общим рендером: обычный текст на месте, разметка — нет.
    private func assertRendered(_ app: XCUIApplication, _ place: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let all = app.descendants(matching: .any)
        for raw in ["| Место |", "```widget", "**Один и тот же", "| --- |"] {
            let hit = all.matching(NSPredicate(format: "label CONTAINS %@", raw)).firstMatch
            XCTAssertFalse(hit.exists, "\(place): виден сырой текст роли «\(raw)»", file: file, line: line)
        }
        let text = all.matching(NSPredicate(format: "label CONTAINS %@", "одинаково")).firstMatch
        XCTAssertTrue(text.exists, "\(place): текст ответа роли не показан", file: file, line: line)
    }

    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication, limit: Int = 25) -> Bool {
        var tries = 0
        while tries < limit {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
            tries += 1
        }
        return element.exists
    }

    @discardableResult
    private func openSection(_ app: XCUIApplication, _ title: String) -> Bool {
        let header = app.buttons[title]
        var tries = 0
        while tries < 25 {
            if header.exists, header.isHittable { header.tap(); return true }
            app.swipeUp()
            tries += 1
        }
        return false
    }

    private func waitForCard(_ app: XCUIApplication) {
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "QA: проверка")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 40), "Карточка не открылась")
    }

    /// Комментарий карточки, результат шага плана, итог задачи — один ответ роли.
    func testSameRoleReplyEverywhereInCard() {
        let app = launch("task:qa-live")
        waitForCard(app)

        // 1. Комментарий карточки.
        XCTAssertTrue(openSection(app, "Лента активности"), "Нет ленты активности")
        let comment = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "одинаково")).firstMatch
        XCTAssertTrue(scrollTo(comment, app), "Комментарий роли не найден")
        assertRendered(app, "комментарий карточки")
        shot(app, "comment")

        // 2. Результат шага плана.
        XCTAssertTrue(openSection(app, "Подзадачи"), "Нет секции «Подзадачи»")
        let step = app.staticTexts["Проверить результат по критериям приёмки"]
        XCTAssertTrue(scrollTo(step, app), "Шаг не найден")
        step.tap()
        let stepText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "одинаково")).firstMatch
        XCTAssertTrue(stepText.waitForExistence(timeout: 10), "Результат шага не открылся")
        assertRendered(app, "результат шага")
        shot(app, "step-result")

        // 3. Итог задачи: вердикт проверяющего и сдача роли.
        let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "закрыть")).firstMatch
        if close.exists { close.tap() }
        XCTAssertTrue(openSection(app, "Итог"), "Нет секции «Итог»")
        let row = app.staticTexts["Проверяющий: принято"]
        if scrollTo(row, app) {
            row.tap()
            let verdict = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "одинаково")).firstMatch
            XCTAssertTrue(verdict.waitForExistence(timeout: 10), "Вердикт не открылся")
            assertRendered(app, "итог задачи (вердикт)")
            shot(app, "outcome-verdict")
        } else {
            XCTFail("Не нашли строку вердикта в секции «Итог»")
        }
    }

    /// Чат с ролью и лента роли — тот же ответ роли.
    func testSameRoleReplyInChat() {
        let app = launch("chat")
        let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Проверка рендера")).firstMatch
        if !chat.waitForExistence(timeout: 40) {
            let row = app.staticTexts["Проверка рендера"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "Чат с ролью не открылся в списке")
            row.tap()
        } else {
            chat.tap()
        }
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "одинаково")).firstMatch
        XCTAssertTrue(scrollTo(reply, app), "Ответ роли в чате не найден")
        assertRendered(app, "чат с ролью (лента роли)")
        shot(app, "chat")
    }
}
