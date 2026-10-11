import XCTest
final class GanttTaskSheetUITests: XCTestCase {
    func testTaskSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let entry = app.buttons["overview.role-load"]
        XCTAssertTrue(entry.waitForExistence(timeout: 25)); entry.tap()
        let chart = app.otherElements["role-load.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 25))
        let bars = app.buttons.matching(NSPredicate(format: "value CONTAINS %@", " — "))
        XCTAssertTrue(bars.firstMatch.waitForExistence(timeout: 25), app.debugDescription)
        let bar = bars.allElementsBoundByIndex.first(where: { $0.isHittable })!
        bar.tap()
        let title = app.descendants(matching: .any)["task.title.content"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertGreaterThan(title.frame.minY, 300)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "gantt-task-sheet"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars.element(boundBy: app.navigationBars.count - 1).swipeDown()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(chart.exists)
    }
}
