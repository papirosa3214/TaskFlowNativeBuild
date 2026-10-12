import XCTest
final class RoleLoadLegendUITests: XCTestCase {
    func testGraphAndPeriodWithoutLegend() {
        let app=XCUIApplication();app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"]="overview";app.launch()
        XCTAssertTrue(app.buttons["overview.role-load"].waitForExistence(timeout:20));app.buttons["overview.role-load"].tap()
        let chart=app.descendants(matching:.any).matching(identifier:"role-load.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout:20))
        for title in ["Заходы","Сейчас","Без исполнителя"] {XCTAssertFalse(app.staticTexts[title].exists)}
        app.buttons["3 дня"].tap()
        expectation(for:NSPredicate(format:"value == %@","3d"),evaluatedWith:chart);waitForExpectations(timeout:10)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="role-load-without-legend";attachment.lifetime = .keepAlways;add(attachment)
    }
}
