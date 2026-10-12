import XCTest
final class RoleLoadPeriodMenuUITests: XCTestCase {
    func testPeriodMenuChangesGraph() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        XCTAssertTrue(app.buttons["overview.role-load"].waitForExistence(timeout: 20))
        app.buttons["overview.role-load"].tap()
        let chart = app.descendants(matching: .any).matching(identifier: "role-load.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 20))
        XCTAssertFalse(app.segmentedControls["role-load.period"].exists)
        for (title, value) in [("3 дня", "3d"), ("Неделя", "week"), ("Сутки", "24h")] {
            app.buttons["role-load.period-menu"].tap()
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
            app.buttons[title].tap()
            expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: chart)
            waitForExpectations(timeout: 15)
        }
        app.buttons["role-load.period-menu"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "role-load-period-menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
