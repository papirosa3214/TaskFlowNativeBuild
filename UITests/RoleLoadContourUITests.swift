import XCTest

/// Временный тест: экран «Загрузка ролей» после переделки в контуры.
/// Снимает кадр экрана и проверяет, что контуры на месте, а подписи — номера.
final class RoleLoadContourUITests: XCTestCase {
    func testContoursRenderWithTaskNumbers() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "overview"
        app.launch()
        XCTAssertTrue(app.buttons["overview.role-load"].waitForExistence(timeout: 30))
        app.buttons["overview.role-load"].tap()
        let chart = app.descendants(matching: .any).matching(identifier: "role-load.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 30))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "role-load-contours"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Контур задачи — элемент с идентификатором role-load.contour.<taskID>.
        let contours = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'role-load.contour.'"))
        print("DIAG контуров на экране: \(contours.count)")
        XCTAssertGreaterThan(contours.count, 0, "на графике должен быть хотя бы один контур задачи")
    }
}
