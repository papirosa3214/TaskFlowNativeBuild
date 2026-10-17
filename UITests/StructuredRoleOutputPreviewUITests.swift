import XCTest

final class StructuredRoleOutputPreviewUITests: XCTestCase {
    func testServerEnvelopeAndTypedBlocksRenderInRoleChat() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_CHAT_READING_PREVIEW"] = "1"
        app.launchEnvironment["TASKFLOW_STRUCTURED_OUTPUT_PREVIEW"] = "1"
        app.launch()

        let longCell = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Длинная ячейка для проверки переноса")).firstMatch
        XCTAssertTrue(longCell.waitForExistence(timeout: 20))
        for _ in 0..<5 where !longCell.isHittable { app.swipeDown() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.structured-output.table").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.structured-output.chart").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.structured-output.report").firstMatch.exists)

        let followingCell = app.staticTexts["Следующая строка"]
        XCTAssertTrue(followingCell.exists)
        XCTAssertGreaterThan(longCell.frame.height, 40, "Ячейка должна занимать несколько строк")
        XCTAssertGreaterThan(followingCell.frame.minY, longCell.frame.maxY - 2, "Следующая строка не должна накладываться на многострочную ячейку")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "structured-role-output-server-and-v1-blocks"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
