import XCTest
/// Временный тест LOCK-WIDGET-TASK-LINK-20261013: кнопка виджета открывает карточку.
final class WidgetTaskLinkUITests: XCTestCase {
    func testWidgetOpensTask() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
        app.launch()
        let open = app.buttons["widget-card-open-task"].firstMatch
        if !open.waitForExistence(timeout: 20) {
            let secretary = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Секретар")).firstMatch
            if secretary.waitForExistence(timeout: 10) { secretary.tap() }
        }
        for _ in 0..<8 where !(open.exists && open.isHittable) { app.swipeDown() }
        let s0 = XCTAttachment(screenshot: app.screenshot()); s0.name = "chat"; s0.lifetime = .keepAlways; add(s0)
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        // Поднять кнопку над полем ввода, иначе нажатие уходит в поле.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        sleep(1)
        open.tap()
        let details = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Сведения")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 20), "карточка не открылась")
        let s1 = XCTAttachment(screenshot: app.screenshot()); s1.name = "task"; s1.lifetime = .keepAlways; add(s1)
    }
}
