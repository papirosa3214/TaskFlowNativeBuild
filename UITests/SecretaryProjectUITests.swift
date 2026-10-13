import XCTest
/// Временный диагностический тест: виден ли проект «Учёт личных финансов».
final class SecretaryProjectUITests: XCTestCase {
    func testProjectVisible() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "projects"
        app.launch()
        sleep(6)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "projects"; a.lifetime = .keepAlways; add(a)
        let p = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "личных финансов")).firstMatch
        for _ in 0..<5 where !p.exists { app.swipeUp() }
        let b = XCTAttachment(screenshot: app.screenshot()); b.name = "projects-scrolled"; b.lifetime = .keepAlways; add(b)
        XCTAssertTrue(p.exists, "проекта нет в списке")
    }
}
