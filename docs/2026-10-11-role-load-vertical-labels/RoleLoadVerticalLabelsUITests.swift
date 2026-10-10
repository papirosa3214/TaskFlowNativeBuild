import XCTest
final class RoleLoadVerticalLabelsUITests: XCTestCase {
    func testVerticalLabelsDayAndWeek() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let entry = app.buttons["overview.role-load"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), app.debugDescription)
        entry.tap()
        let chart = app.otherElements["role-load.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 30), app.debugDescription)
        let label = app.descendants(matching: .any)["role-load.label.analyst"]
        XCTAssertTrue(label.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertLessThanOrEqual(label.frame.width, 50)
        XCTAssertEqual(label.label, "Аналитик")
        capture(app, "01-day-vertical-labels")
        app.segmentedControls.buttons["Неделя"].tap()
        expectation(for: NSPredicate(format: "value == %@", "week"), evaluatedWith: chart)
        waitForExpectations(timeout: 30)
        XCTAssertLessThanOrEqual(label.frame.width, 50)
        capture(app, "02-week-vertical-labels")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
