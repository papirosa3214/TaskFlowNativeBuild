import XCTest

final class RoleLoadRowsUITests: XCTestCase {
    func testRoleCanCollapseAndRestoreWithoutChangingOtherRoles() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let entry = app.buttons["overview.role-load"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()
        let analyst = app.buttons["role-load.label.analyst"]
        XCTAssertTrue(analyst.waitForExistence(timeout: 30))
        XCTAssertGreaterThanOrEqual(analyst.frame.height, 103)
        XCTAssertEqual(analyst.value as? String, "Развёрнута")
        let originalHeight = analyst.frame.height
        let other = app.buttons["role-load.label.critic"]
        let otherHeight = other.exists ? other.frame.height : nil
        capture(app, name: "expanded")

        analyst.tap()
        XCTAssertTrue(app.buttons["role-load.expand.analyst"].waitForExistence(timeout: 5))
        XCTAssertEqual(analyst.value as? String, "Свёрнута")
        XCTAssertEqual(analyst.frame.height, 44, accuracy: 1)
        if let otherHeight { XCTAssertEqual(other.frame.height, otherHeight, accuracy: 1) }
        capture(app, name: "collapsed")

        app.buttons["role-load.expand.analyst"].tap()
        XCTAssertEqual(analyst.value as? String, "Развёрнута")
        XCTAssertEqual(analyst.frame.height, originalHeight, accuracy: 1)
        capture(app, name: "restored")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "role-load-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
