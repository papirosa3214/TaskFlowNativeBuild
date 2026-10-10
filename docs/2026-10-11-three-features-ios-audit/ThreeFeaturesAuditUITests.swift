import XCTest

final class ThreeFeaturesAuditUITests: XCTestCase {
    func testAuditLiveGanttV2WebhooksAndLocalDiagnostics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        let entry = app.buttons["overview.role-load"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), app.debugDescription)
        entry.tap()
        let chart = app.otherElements["role-load.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 30), app.debugDescription)
        capture(app, "01-live-gantt-day")
        app.segmentedControls.buttons["Неделя"].tap()
        expectation(for: NSPredicate(format: "value == %@", "week"), evaluatedWith: chart)
        waitForExpectations(timeout: 30)
        capture(app, "02-live-gantt-week")
        app.terminate()

        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
        app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3327"
        app.launch()
        let integrations = app.buttons["Интеграции"].firstMatch
        XCTAssertTrue(integrations.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<6 { if integrations.isHittable { break }; app.swipeUp() }
        integrations.tap()
        let hooks = app.buttons["integrations.webhooks"]
        XCTAssertTrue(hooks.waitForExistence(timeout: 15), app.debugDescription)
        hooks.tap()
        XCTAssertTrue(app.staticTexts["Запуск оркестратора не подтверждён"].waitForExistence(timeout: 15), app.debugDescription)
        // Fixture has a real V2 ack=true. This records the current UI defect.
        capture(app, "03-v2-ack-ignored")
        app.buttons["webhooks.test.audit-hook"].tap()
        XCTAssertTrue(app.alerts["Проверка вебхука"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Не удалось разобрать ответ сервера")).firstMatch.exists, app.alerts.debugDescription)
        capture(app, "04-v2-delivery-decoding-error")
        app.alerts.buttons["Готово"].tap()
        app.terminate()

        app.launchEnvironment.removeValue(forKey: "TASKFLOW_DEBUG_ROUTE")
        app.launchEnvironment["TASKFLOW_DIAGNOSTICS_PREVIEW"] = "1"
        app.launch()
        let diagnostics = app.buttons["server-settings-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15), app.debugDescription)
        diagnostics.tap()
        XCTAssertTrue(app.descendants(matching: .any)["app-diagnostics-screen"].waitForExistence(timeout: 10))
        capture(app, "05-local-diagnostics-not-server-journal")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
