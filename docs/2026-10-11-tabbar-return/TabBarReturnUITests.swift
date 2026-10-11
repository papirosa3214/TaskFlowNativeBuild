import XCTest

final class TabBarReturnUITests: XCTestCase {
    func testProjectBackAndCreateMenu() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        XCTAssertTrue(app.buttons["tab.projects"].waitForExistence(timeout: 20))
        app.buttons["tab.projects"].tap()
        let project = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "NewTodoist")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 20))
        capture(app, "projects-root-clean")
        project.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab.add"].isHittable)
        capture(app, "project-pushed")
        // A slow edge drag exposes the previous root during UIKit's own transition.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["tab.add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab.add"].isHittable)
        capture(app, "projects-after-swipe")
        app.buttons["tab.add"].tap()
        XCTAssertTrue(app.buttons["create.task"].waitForExistence(timeout: 5))
        capture(app, "create-menu-on-root")
        app.buttons["tab.add"].tap()
        XCTAssertFalse(app.buttons["create.task"].exists)
        app.buttons["tab.directory"].tap()
        XCTAssertTrue(app.staticTexts["Обзор"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
