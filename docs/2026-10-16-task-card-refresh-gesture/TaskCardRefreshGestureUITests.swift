import XCTest

/// Настоящие карточки: прямой вход и открытие из refreshable-списка.
final class TaskCardRefreshGestureUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRefreshDoesNotCaptureCardGestures() {
        for route in ["task:caecdeee-02e2-43e8-8510-8da6b78cc860", "alltasks"] {
            let app = XCUIApplication()
            app.launchArguments += ["-hints.enabled", "NO"]
            app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = route
            app.launch()
            let name = route == "alltasks" ? "list" : "direct"
            if route == "alltasks" {
                let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.task.")).firstMatch
                guard row.waitForExistence(timeout: 30) else {
                    XCTFail("Не загрузился настоящий список задач")
                    shot(app, "list-not-loaded")
                    return
                }
                row.tap()
            }
            let card = app.collectionViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task.content.")).firstMatch
            guard card.waitForExistence(timeout: 30) else {
                XCTFail("Не открылась карточка: \(route)")
                shot(app, "\(name)-not-opened")
                return
            }
            let refresh = card.value as? String ?? "unknown"
            let medium = card.frame.height
            shot(app, "\(name)-medium-\(refresh)")
            card.swipeUp(velocity: .slow)
            let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                card.exists && card.frame.height > medium + 80
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed, "Не раскрывается: \(name)")
            shot(app, "\(name)-large")
            if card.exists {
                card.swipeDown(velocity: .slow)
                let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    card.exists && abs(card.frame.height - medium) < 50
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed, "Не сворачивается: \(name)")
                shot(app, "\(name)-collapsed")
            }
            if card.exists { card.swipeDown(velocity: .fast) }
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !card.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, "Не закрывается: \(name)")
            shot(app, "\(name)-after-dismiss")
            XCTAssertEqual(refresh, "refresh:none", "Карточка наследует refresh экрана-источника: \(name)")
            app.terminate()
        }
    }

    func testCalendarInboxCardGestures() {
        let app = XCUIApplication()
        app.launchArguments += ["-hints.enabled", "NO", "-plannerSection", "today", "-today_layout", "list", "-today_list_tab", "inbox"]
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "upcoming"
        app.launch()
        let row = app.buttons["today.task-row"].firstMatch
        guard row.waitForExistence(timeout: 30) else {
            shot(app, "inbox-not-loaded")
            XCTFail("Нет строки задачи во Входящих")
            return
        }
        shot(app, "inbox-source")
        row.tap()
        let card = app.collectionViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task.content.")).firstMatch
        guard card.waitForExistence(timeout: 30) else {
            shot(app, "inbox-card-not-opened")
            XCTFail("Карточка из Входящих не открылась")
            return
        }
        let refresh = card.value as? String ?? "unknown"
        let medium = card.frame.height
        shot(app, "inbox-medium-\(refresh)")
        card.swipeUp(velocity: .slow)
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            card.exists && card.frame.height > medium + 80
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed, "Карточка Входящих не раскрывается")
        shot(app, "inbox-large")
        if card.exists {
            card.swipeDown(velocity: .slow)
            let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                card.exists && abs(card.frame.height - medium) < 50
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed, "Карточка Входящих не сворачивается")
            shot(app, "inbox-after-pull-down")
        }
        if card.exists { card.swipeDown(velocity: .fast) }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !card.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, "Карточка Входящих не закрывается")
        shot(app, "inbox-after-dismiss")
        XCTAssertEqual(refresh, "refresh:none", "В карточку Входящих попало обновление от родительского календаря")
    }

}
