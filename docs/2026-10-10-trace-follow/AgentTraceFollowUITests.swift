import XCTest

final class AgentTraceFollowUITests: XCTestCase {
    func testGraphSheetShowsTraceAndReplaysHistory() {
        let app = XCUIApplication()
        let id = "e34b032c-4aef-4d42-bd1d-1cf557d27c23"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:" + id
        app.launchEnvironment["TASKFLOW_AGENT_TRACE_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_AGENT_TRACE_LONG"] = "1"
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
        XCTAssertTrue(app.scrollViews["agent-trace-scroll"].exists)
        let page = app.collectionViews.containing(.other, identifier: "agent-trace").firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        let last = app.otherElements["agent-trace-span-preview-23"]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(last.isHittable, "Initially opens at the latest operation")
        app.buttons["agent-trace-next-preview"].tap()
        let incoming = app.otherElements["agent-trace-span-incoming"]
        XCTAssertTrue(incoming.waitForExistence(timeout: 15))
        XCTAssertTrue(incoming.isHittable, "New operation must scroll into view")
        XCTAssertTrue(incoming.label.contains("Правка"))
        let finished = XCTAttachment(screenshot: app.screenshot()); finished.name = "agent-trace-follow"; finished.lifetime = .keepAlways; add(finished)
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Ожидает")).firstMatch.waitForExistence(timeout: 5))
        let replay = XCTAttachment(screenshot: app.screenshot()); replay.name = "agent-trace-replay"; replay.lifetime = .keepAlways; add(replay)
        app.buttons["agent-trace-live"].tap()
        XCTAssertTrue(incoming.isHittable)
    }
}
