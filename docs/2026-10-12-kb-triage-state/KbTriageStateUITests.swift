import XCTest

/// Временный тест (LOCK-KB-TRIAGE-STATE): строка «Разбор заметок» в разделе
/// «Состояние системы» — рядом с «Системой», «Авторевьюером», «Расписанием».
final class KbTriageStateUITests: XCTestCase {
    func testTriageRowShot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launch()

        let row = app.staticTexts["Разбор заметок"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "строки «Разбор заметок» нет в настройках")

        // Прокручиваем, пока строка не окажется реально видимой на экране:
        // `exists` истинно и для элемента за пределами кадра.
        for _ in 0..<8 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "строка «Разбор заметок» не доехала до экрана")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "kb-triage-row"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
