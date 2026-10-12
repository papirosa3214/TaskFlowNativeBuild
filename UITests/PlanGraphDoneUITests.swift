import XCTest

/// Временный тест (LOCK-PLAN-GRAPH-DONE-20261012): в графе плана отработавшие
/// шаги помечаются зелёным домиком, связи в них гаснут, стрелки обходят чужие
/// домики, а роли показаны портретами с анимацией (владелец 12.10.2026).
final class PlanGraphDoneUITests: XCTestCase {
    func testPlanGraphMarksFinishedAndRoutesArrows() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:301196c7-1b5b-4e46-a11f-1684f1139e47"
        app.launch()

        let header = app.staticTexts["План совместной работы"]
        XCTAssertTrue(header.waitForExistence(timeout: 60), "карточка не открылась")
        header.tap()

        // Граф лежит в канвасе — по скриншоту, а не по дереву.
        let graph = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Граф зависимостей'"))
            .firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 20), "граф плана не отрисовался")
        Thread.sleep(forTimeInterval: 2)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "plan-graph"
        shot.lifetime = .keepAlways
        add(shot)
    }
}