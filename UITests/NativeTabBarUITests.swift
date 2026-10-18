import XCTest

final class NativeTabBarUITests: XCTestCase {
    func testSystemTabsAndSeparateCreateAction() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hints.enabled", "NO", "-taskflow_tabbar_pill_enabled", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Требуется системный таббар")
        let tabBar = app.tabBars.firstMatch
        for title in ["Проекты", "Планирование", "Чат", "Обзор"] {
            let button = tabBar.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 15))
            button.tap()
            XCTAssertTrue(button.isSelected, "Системный выбор вкладки: \(title)")
        }
        let plus = tabBar.buttons["Создать"]
        XCTAssertTrue(plus.exists)
        plus.tap()
        XCTAssertTrue(app.buttons["Задача"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Обзор"].isSelected, "Плюс открывает меню, сохраняя текущий раздел")
        plus.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Задача"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "system-tabview-apple"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
