import XCTest

/// Запускается с локальной фикстурой, полученной из серверного теста сдачи артефакта.
final class SubmissionReceiptUITests: XCTestCase {
    func testStageReportOpensNotesEditor() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:report-fixture"
        app.launch()
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 20))
        grabber.swipeUp()
        if !app.buttons["plan-node-build"].exists {
            let section = app.buttons["task-card.report-fixture.section.collaborationPlan"]
            if !section.exists { app.swipeUp() }
            XCTAssertTrue(section.waitForExistence(timeout: 10))
            section.tap()
        }
        let stage = app.buttons["plan-node-build"]
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        stage.tap()
        XCTAssertTrue(app.staticTexts["Сдача подтверждена сервером"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Сдача основным сервером не подтверждена"].exists)
        let report = app.buttons["plan-result-report"]
        if !report.exists { app.swipeUp() }
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        let resultShot = XCTAttachment(screenshot: app.screenshot())
        resultShot.name = "stage-report-link"; resultShot.lifetime = .keepAlways; add(resultShot)
        report.tap()
        XCTAssertTrue(app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "Проверка доступна владельцу")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Не удалось загрузить заметку"].exists)
        let noteShot = XCTAttachment(screenshot: app.screenshot())
        noteShot.name = "stage-report-note"; noteShot.lifetime = .keepAlways; add(noteShot)
    }
}
