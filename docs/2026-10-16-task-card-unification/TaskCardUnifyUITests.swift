import XCTest

/// Временная приёмка настоящей общей шторки, без сохранения/изменения задач.
final class TaskCardUnifyUITests: XCTestCase {
    private let taskID = "caecdeee-02e2-43e8-8510-8da6b78cc860"

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUnifiedCardAndQuickAdd() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hints.enabled", "NO"]
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:\(taskID)"
        app.launch()
        let content = app.descendants(matching: .any)["task.content.\(taskID)"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30))
        shot(app, "01-medium")
        let mediumHeight = content.frame.height
        content.swipeUp(velocity: .slow)
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            content.frame.height > mediumHeight + 80
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        shot(app, "02-large")

        let links = app.buttons["task-card.\(taskID).section.linkedTasks"]
        for _ in 0..<12 {
            if links.isHittable { break }
            content.swipeUp()
        }
        XCTAssertTrue(links.isHittable)
        let create = app.buttons["task-card.links.create-child"]
        if !create.exists { links.tap() }
        for _ in 0..<4 {
            if create.isHittable { break }
            content.swipeUp()
        }
        XCTAssertTrue(create.isHittable)
        XCTAssertTrue(app.buttons["task-card.links.link-child"].exists)
        shot(app, "03-links")
        create.tap()
        let hide = app.buttons["quickadd.keyboard.dismiss"]
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["quickadd.keyboard.dictation"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Скрыть клавиатуру")).count, 1)
        shot(app, "04-child-keyboard")
        hide.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "count == 0"),
            evaluatedWith: app.keyboards)], timeout: 5) == .completed)
        shot(app, "05-child-keyboard-hidden")

        // Новый запуск сбрасывает несохранённую короткую карточку.
        app.terminate()
        app.launch()
        XCTAssertTrue(content.waitForExistence(timeout: 30))
        content.swipeUp(velocity: .slow)
        for _ in 0..<8 {
            if !content.exists { break }
            content.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "exists == false"),
            evaluatedWith: content)], timeout: 5) == .completed)
        shot(app, "06-dismissed")
    }

    /// Дополнительный прогон проверяет только оставшийся шаг: закрытие и возврат.
    func testCardDismissalReturnsToSource() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hints.enabled", "NO"]
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:\(taskID)"
        app.launch()
        let content = app.descendants(matching: .any)["task.content.\(taskID)"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30))
        content.swipeUp(velocity: .slow)
        shot(app, "07-before-dismissal")
        for _ in 0..<4 {
            if !content.exists { break }
            content.swipeDown(velocity: .fast)
        }
        XCTAssertFalse(content.exists, "Карточка должна закрыться свайпом вниз")
        XCTAssertTrue(app.staticTexts["ОБЗОР"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ОБЗОР"].isHittable)
        shot(app, "08-returned-to-source")
    }

}
