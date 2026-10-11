import XCTest
final class ProjectCancellationUITests: XCTestCase {
    func testCancelledRefreshKeepsProjectsWithoutError() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launchEnvironment["TASKFLOW_PROJECT_CANCELLATION_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["TaskFlow - NewTodoist"].waitForExistence(timeout: 25))
        app.buttons["projects.test.cancel"].tap()
        XCTAssertTrue(app.staticTexts["projects.test.cancelled"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "CancellationError")).count, 0)
        XCTAssertTrue(app.staticTexts["TaskFlow - NewTodoist"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "projects-cancelled-refresh"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
