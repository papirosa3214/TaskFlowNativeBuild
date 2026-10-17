import XCTest
@testable import TaskFlow

final class MarkdownDocumentRendererTests: XCTestCase {
    func testAdapterPreservesDocumentStructureAndInlineMarks() {
        let markdown = """
        # Заголовок **важно**

        - Вложенный [пункт](https://example.com)
          1. Дочерний

        | Имя | Значение |
        | --- | --- |
        | Длинный | **текст** |
        | \\*literal\\* | `a|b` |

        ```swift
        let value = 1
        ```
        """

        let blocks = MarkdownDocumentAdapter.blocks(from: markdown)

        XCTAssertEqual(blocks.count, 5)
        guard case let .heading(level, headingRuns) = blocks[0] else {
            return XCTFail("Первый блок должен быть заголовком")
        }
        XCTAssertEqual(level, 1)
        XCTAssertTrue(headingRuns.contains { $0.text == "важно" && $0.bold })

        guard case let .listItem(kind: .bullet, depth: 0, runs: bulletRuns) = blocks[1] else {
            return XCTFail("Второй блок должен быть пунктом списка")
        }
        XCTAssertTrue(bulletRuns.contains { $0.text == "пункт" && $0.linkHref == "https://example.com" })

        guard case let .listItem(kind: .ordered, depth: 1, runs: nestedRuns) = blocks[2] else {
            return XCTFail("Третий блок должен быть вложенным нумерованным пунктом")
        }
        XCTAssertTrue(nestedRuns.contains { $0.text == "Дочерний" })

        guard case .table(let rows) = blocks[3] else {
            return XCTFail("Четвёртый блок должен быть таблицей")
        }
        XCTAssertEqual(rows.first?.cells.count, 2)
        XCTAssertTrue(rows[1].cells.last?.runs.contains { $0.text == "текст" && $0.bold } == true)
        XCTAssertTrue(rows[2].cells.first?.runs.contains { $0.text == "*literal*" && !$0.italic } == true)
        XCTAssertTrue(rows[2].cells.last?.runs.contains { $0.text == "a|b" && $0.code } == true)

        guard case let .code(text, language) = blocks[4] else {
            return XCTFail("Пятый блок должен быть кодом")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(text, "let value = 1")
    }

    func testUnclosedCodeFenceRemainsVisibleAsText() {
        let blocks = MarkdownDocumentAdapter.blocks(from: "```swift\nlet value = 1")

        XCTAssertTrue(blocks.contains { block in
            guard case let .paragraph(runs) = block else { return false }
            return runs.map(\.text).joined().contains("let value = 1")
        })
    }
}
