import XCTest

final class AgentTraceUITests: XCTestCase {
    func testGraphSheetShowsTraceAndReplaysHistory() {
        let app = XCUIApplication()
        let id = "e34b032c-4aef-4d42-bd1d-1cf557d27c23"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:" + id
        app.launchEnvironment["TASKFLOW_AGENT_TRACE_PREVIEW"] = "1"
        app.launch()
        let section = app.buttons["task-card.\(id).section.collaborationPlan"]
        XCTAssertTrue(section.waitForExistence(timeout: 30))
        let node = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan-node-")).firstMatch
        if !node.exists { section.tap() }
        XCTAssertTrue(node.waitForExistence(timeout: 15)); node.tap()
        let slider = app.sliders["agent-trace-scrubber"]
        if !slider.exists { app.swipeUp() }
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ход работы"].exists)
        let finished = XCTAttachment(screenshot: app.screenshot()); finished.name = "agent-trace-finished"; finished.lifetime = .keepAlways; add(finished)
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ожидает")).firstMatch.waitForExistence(timeout: 5))
        let replay = XCTAttachment(screenshot: app.screenshot()); replay.name = "agent-trace-replay"; replay.lifetime = .keepAlways; add(replay)
        app.buttons["agent-trace-live"].tap()
        XCTAssertTrue(app.staticTexts["Запуск завершён"].exists)
    }
}
