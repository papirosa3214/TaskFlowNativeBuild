import XCTest
@available(iOS 26.0, *)
final class TabBarGlassUITests: XCTestCase {
    func testWaveLightAndNavigation() {
        checkTabs(mode: "wave")
    }

    func testSteadyDiffuseLight() {
        checkTabs(mode: "steady")
    }

    private func checkTabs(mode: String) {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launchEnvironment["TASKFLOW_TAB_GLOW_MODE"] = mode
        app.launch()
        XCTAssertTrue(app.buttons["tab.directory"].waitForExistence(timeout: 20))
        capture(app, "tabbar-overview")
        for id in ["tab.projects", "tab.upcoming", "tab.chat", "tab.directory"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists, id)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
            button.tap()
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: button)
            waitForExpectations(timeout: 5)
            capture(app, mode + "-" + id)
            Thread.sleep(forTimeInterval: 3.3)
            capture(app, mode + "-settled-" + id)
        }
        XCTAssertTrue(app.staticTexts["Обзор"].waitForExistence(timeout: 5))
        let create = app.buttons["tab.add"]
        XCTAssertGreaterThanOrEqual(create.frame.width, 44)
        XCTAssertGreaterThanOrEqual(create.frame.height, 44)
        create.tap()
        expectation(for: NSPredicate(format: "label == %@", "Закрыть меню создания"), evaluatedWith: create)
        waitForExpectations(timeout: 5)
        capture(app, mode + "-create-open")
        Thread.sleep(forTimeInterval: 3.3)
        capture(app, mode + "-create-settled")
        create.tap()
        expectation(for: NSPredicate(format: "label == %@", "Создать"), evaluatedWith: create)
        waitForExpectations(timeout: 5)
        capture(app, mode + "-create-closed")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
