import XCTest

final class ContextObservabilityUITests: XCTestCase {
    func testContextAndJevUsageReadOnly() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let entry = app.buttons["overview.role-load"]
        XCTAssertTrue(entry.waitForExistence(timeout: 25), app.debugDescription)
        entry.tap()
        let context = app.staticTexts["Контекст и JEV"]
        for _ in 0..<12 {
            if context.exists && context.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(context.waitForExistence(timeout: 15), app.debugDescription)
        let tracked = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Учёт с ")).firstMatch
        XCTAssertTrue(tracked.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Не удалось загрузить журнал контекста. Повторяем автоматически."].exists)
        capture(app, "Контекст и JEV — Загрузка ролей")
        app.terminate()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launch()
        let jev = app.buttons["settings-jev"]
        let ai = app.buttons["Искусственный интеллект"]
        for _ in 0..<12 {
            if jev.exists && jev.isHittable { break }
            if ai.exists && ai.isHittable && (ai.value as? String ?? "").lowercased().contains("свернут") {
                ai.tap()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(jev.waitForExistence(timeout: 15), app.debugDescription)
        jev.tap()
        let expense = app.staticTexts["Расход в TaskFlow"]
        for _ in 0..<8 {
            if expense.exists && expense.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(expense.waitForExistence(timeout: 20), app.debugDescription)
        let usage = app.staticTexts["Стоимость и баланс провайдером не предоставлены"]
        for _ in 0..<6 {
            if usage.exists && usage.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(usage.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Не удалось загрузить расход. Повторяем автоматически."].exists)
        capture(app, "Расход текущего ключа JEV")
        app.terminate()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
