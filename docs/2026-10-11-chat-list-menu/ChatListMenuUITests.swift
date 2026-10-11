import XCTest
final class ChatListMenuUITests: XCTestCase {
    func testListMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()
        let menu = app.buttons["chats.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        XCTAssertFalse(app.segmentedControls.buttons["Личные"].exists)
        capture(app,"personal-no-tabs")
        menu.tap()
        let projects = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Чаты проектов")).firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 5), app.debugDescription)
        projects.tap()
        XCTAssertTrue(app.staticTexts["Чаты проектов"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        capture(app,"projects-from-menu")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertFalse(app.segmentedControls.buttons["Личные"].exists)
    }
    private func capture(_ app:XCUIApplication,_ name:String) {
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
