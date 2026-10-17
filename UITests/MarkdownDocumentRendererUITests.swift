import XCTest

final class MarkdownDocumentRendererUITests: XCTestCase {
    func testMarkdownDocumentPreviewRendersLongTableCellAndFollowingRow() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_MARKDOWN_DOCUMENT_PREVIEW"] = "1"
        app.launch()

        let heading = app.staticTexts["Предпросмотр документа"]
        XCTAssertTrue(heading.waitForExistence(timeout: 20))

        let longCell = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Длинная ячейка для проверки переноса текста")).firstMatch
        XCTAssertTrue(longCell.exists)
        for _ in 0..<5 where !longCell.isHittable { app.swipeUp() }

        let followingCell = app.staticTexts["Следующая строка"]
        XCTAssertTrue(followingCell.exists)
        XCTAssertTrue(app.staticTexts["*literal*"].exists, "Экранированные звёздочки должны остаться обычным текстом")
        XCTAssertTrue(app.staticTexts["a|b"].exists, "Вертикальная черта внутри inline-кода не должна повреждаться")
        XCTAssertGreaterThan(longCell.frame.height, 40, "Ячейка должна занимать несколько строк")
        XCTAssertGreaterThan(followingCell.frame.minY, longCell.frame.maxY - 2, "Следующая строка не должна перекрывать длинную ячейку")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "markdown-document-preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
