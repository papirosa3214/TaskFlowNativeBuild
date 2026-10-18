import XCTest

/// Временный сценарий LOCK-TABBAR-PILL-20261018: вид пилюли с линзой, ход
/// линзы по вкладкам и переключение тумблера «Таббар-пилюля» в настройках.
/// После приёмки владельцем файл удаляется.
final class PillTabBarUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["tab.directory"].tap()
        let settings = app.staticTexts["Настройки"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
    }

    func testPillAndToggle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["tab.directory"].waitForExistence(timeout: 40))

        // Состояние панели живёт в UserDefaults симулятора и переживает прогоны:
        // приводим тумблер к пилюле, иначе результат теста зависит от того, чем закончился
        // предыдущий запуск (18.10.2026: прогон начался с выключенной пилюли).
        openSettings(app)
        let pillSwitch = app.switches["settings.pillTabBar"]
        XCTAssertTrue(pillSwitch.waitForExistence(timeout: 15))
        if pillSwitch.value as? String != "1" { pillSwitch.tap() }
        XCTAssertEqual(pillSwitch.value as? String, "1", "Пилюля должна включаться тумблером")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["tab.directory"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.2)
        capture(app, "01-pill-overview")

        // Линза переехала за активную вкладку.
        XCTAssertTrue(app.buttons["tab.chat"].exists)
        app.buttons["tab.chat"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        capture(app, "02-pill-chat-lens-moved")

        XCTAssertTrue(app.buttons["tab.upcoming"].exists)
        app.buttons["tab.upcoming"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        capture(app, "03-pill-upcoming")

        // Тумблер в настройках возвращает нынешний таббар.
        openSettings(app)
        let toggle = app.switches["settings.pillTabBar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
                toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        capture(app, "04-settings-toggle-off")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["tab.directory"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.0)
        capture(app, "05-classic-tabbar")

        // И обратно — пилюля.
        openSettings(app)
        let back = app.switches["settings.pillTabBar"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        back.tap()
        XCTAssertEqual(back.value as? String, "1")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["tab.directory"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.2)
        capture(app, "06-pill-back")

        // Меню создания открывается красной «+» справа вне пилюли.
        XCTAssertTrue(app.buttons["tab.add"].exists)
        app.buttons["tab.add"].tap()
        XCTAssertTrue(app.buttons["create.task"].waitForExistence(timeout: 10),
                      "Красная «+» вне пилюли должна открывать меню создания")
        Thread.sleep(forTimeInterval: 0.8)
        capture(app, "07-pill-create-menu")
    }
}
