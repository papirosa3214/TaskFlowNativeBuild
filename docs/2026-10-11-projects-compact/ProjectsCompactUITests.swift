import XCTest
final class ProjectsCompactUITests: XCTestCase {
    func testCompactProjectRowsAndSearchMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()
        let work = app.descendants(matching: .any)["projects.status.В работе"]
        XCTAssertTrue(work.waitForExistence(timeout: 25), app.debugDescription)
        for name in ["На проверке", "Заблокированы", "Пропали"] {
            let item = app.descendants(matching: .any)["projects.status.\(name)"]
            XCTAssertTrue(item.exists)
            XCTAssertEqual(item.frame.midY, work.frame.midY, accuracy: 1)
        }
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "projects-compact"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Действия с проектами"].tap()
        app.buttons["Поиск проектов"].tap()
        XCTAssertTrue(app.textFields["projects.search.field"].waitForExistence(timeout: 5))
        app.buttons["Готово"].tap()
    }
}
