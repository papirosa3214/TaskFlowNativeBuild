import XCTest

final class TaskCardLoadingUITests: XCTestCase {
    func testCardOpensAndSurvivesForeground() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hints.enabled", "NO"]
        let taskID = "07d85e49-79c4-43cd-92ab-246703815a97"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:\(taskID)"
        app.launch()
        let card = app.collectionViews["task.content.\(taskID)"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let title = app.descendants(matching: .any)["task.title.content"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            XCTAssertTrue(title.waitForExistence(timeout: 15))
        }
    }
}
