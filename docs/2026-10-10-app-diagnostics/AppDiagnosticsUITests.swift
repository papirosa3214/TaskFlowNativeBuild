import XCTest

final class AppDiagnosticsUITests: XCTestCase {
    func testSettingsEntryShowsActualPacerWorkAndSleepingQueue() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DIAGNOSTICS_PREVIEW"] = "1"
        app.launch()
        let entry = app.buttons["server-settings-diagnostics"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["История изменений"].exists)
        capture(app, "settings-white-history-and-diagnostics")
        app.buttons["diagnostics-preview-stream"].tap()
        XCTAssertTrue(app.staticTexts["diagnostics-preview-complete"].waitForExistence(timeout: 20))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let queues = app.descendants(matching: .any).matching(identifier: "diagnostics-queues").firstMatch
        XCTAssertTrue(queues.waitForExistence(timeout: 5))
        XCTAssertEqual(queues.value as? String, "Спят")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "diagnostics-collection").firstMatch.value as? String, "Постоянно")
        capture(app, "diagnostics-queue-asleep")
        let list = app.descendants(matching: .any).matching(identifier: "app-diagnostics-screen").firstMatch
        let updates = app.descendants(matching: .any).matching(identifier: "diagnostics-count-updates").firstMatch
        for _ in 0..<4 {
            if updates.exists && updates.isHittable { break }
            list.swipeUp()
        }
        let ticks = app.descendants(matching: .any).matching(identifier: "diagnostics-count-ticks").firstMatch
        XCTAssertGreaterThan(Int(ticks.value as? String ?? "") ?? 0, 0)
        XCTAssertGreaterThan(Int(updates.value as? String ?? "") ?? 0, 0)
        capture(app, "diagnostics-queue-asleep-and-counters")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
