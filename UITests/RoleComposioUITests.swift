import XCTest

final class RoleComposioUITests: XCTestCase {
    func testOwnerCanOpenComposioFromRoleWithoutChangingSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "agents"
        app.launchEnvironment["TASKFLOW_ROLE_CONTEXT_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Команда"].waitForExistence(timeout: 30))
        let role = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Разработчик'")).firstMatch
        XCTAssertTrue(role.waitForExistence(timeout: 20))
        role.tap()
        let tools = app.buttons["role.composio"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        XCTAssertTrue(app.navigationBars["Composio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Инструменты Composio"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["Composio доступен"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "role-composio-settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Opening the screen must never enable integrations or authorize accounts.
        app.buttons["composio.cancel"].tap()
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
    }
}
