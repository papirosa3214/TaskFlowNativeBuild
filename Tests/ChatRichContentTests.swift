import XCTest
@testable import TaskFlow

/// Клиент адаптирует только готовую структуру сервера.
final class ChatRichContentTests: XCTestCase {
    func testServerDocumentDoesNotInterpretMarkdownInText() throws {
        let doc = JSONValue.object(["type": .string("doc"), "content": .array([
            .object(["type": .string("paragraph"), "content": .array([
                .object(["type": .string("text"), "text": .string("**literal**")])
            ])])
        ])])
        let segments = ChatRichContent.segmentsUncached(fromServer: [.doc(doc, chars: 11)])
        guard case .document(let blocks, _) = segments.first else { return XCTFail("нет документа") }
        XCTAssertEqual(blocks.first?.plainText, "**literal**")
        XCTAssertEqual(blocks.first?.runs.first?.bold, false)
    }

    func testWidgetDataIsLenient() {
        let data = WidgetData.parse(#"{"value":"12,5 °C","n":3,"done":"да","items":[{"label":"x"}]}"#)
        XCTAssertEqual(data?.number("value"), 12.5)
        XCTAssertEqual(data?.string("n"), "3")
        XCTAssertEqual(data?.bool("done"), true)
        XCTAssertEqual(data?.array("items").first?.string("label"), "x")
        XCTAssertNil(WidgetData.parse("не json"))
    }

    func testArtifactTitleAndFragmentWrapping() {
        XCTAssertEqual(ChatHTMLView.title(of: "<html><head><title> Калькулятор </title></head></html>"), "Калькулятор")
        XCTAssertTrue(ChatHTMLView.document("<p>hi</p>").contains("viewport"))
        let full = "<!doctype html><html><body>x</body></html>"
        XCTAssertEqual(ChatHTMLView.document(full), full)
    }
}
