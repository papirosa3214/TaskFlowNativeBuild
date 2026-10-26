import XCTest
@testable import TaskFlow

/// Ответ в чате готовыми блоками сервера (26.10.2026): клиент их только рисует.
final class ChatServerBlockTests: XCTestCase {
    private func decode(_ json: String) throws -> [ChatServerBlock] {
        try JSONDecoder().decode([ChatServerBlock].self, from: Data(json.utf8))
    }

    func testDocumentBlockBecomesNoteBlocksWithoutParsingText() throws {
        let blocks = try decode(#"""
        [{"type":"doc","chars":12,"doc":{"type":"doc","content":[
          {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Итог"}]},
          {"type":"paragraph","content":[{"type":"text","text":"всё ","marks":[{"type":"bold"}]},{"type":"text","text":"готово"}]}
        ]}}]
        """#)
        let segments = ChatRichContent.segmentsUncached(fromServer: blocks)
        guard case .document(let notes, let chars) = segments.first else { return XCTFail("нет документа") }
        XCTAssertEqual(chars, 12)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].kind, .heading(level: 2))
        XCTAssertEqual(notes[1].runs.first?.bold, true)
        XCTAssertEqual(notes[1].plainText, "всё готово")
    }

    func testTableKeepsAlignmentAndMarkedCells() throws {
        let blocks = try decode(#"""
        [{"type":"table","chars":3,"align":["leading","trailing"],
          "header":[[{"type":"text","text":"a"}],[{"type":"text","text":"b"}]],
          "rows":[[[{"type":"text","text":"x","marks":[{"type":"code"}]}],[{"type":"text","text":"y"}]]]}]
        """#)
        guard case .table(let table) = ChatRichContent.segmentsUncached(fromServer: blocks).first else { return XCTFail("нет таблицы") }
        XCTAssertEqual(table.header, ["a", "b"])
        XCTAssertEqual(table.alignments, [.leading, .trailing])
        XCTAssertEqual(table.rows, [["x", "y"]])
        XCTAssertEqual(table.rowRuns?[0][0].first?.code, true)
    }

    func testSpecialBlocksAndUnknownTypes() throws {
        let blocks = try decode(#"""
        [{"type":"widget","json":"{}"},{"type":"html","html":"<b>1</b>"},
         {"type":"pending","kind":"structured_json"},{"type":"новый_тип"}]
        """#)
        XCTAssertEqual(ChatRichContent.segmentsUncached(fromServer: blocks), [
            .widget("{}"), .html("<b>1</b>"), .pending(.structuredJSON),
        ])
    }

    func testMessageDecodesBlocksAndOldServerLeavesThemEmpty() throws {
        let withBlocks = try JSONDecoder().decode(RoleChatMessage.self, from: Data(#"{"id":"m1","text":"ок","is_session_marker":false,"blocks":[{"type":"widget","json":"{}"}]}"#.utf8))
        XCTAssertEqual(withBlocks.blocks, [.widget("{}")])
        let old = try JSONDecoder().decode(RoleChatMessage.self, from: Data(#"{"id":"m2","text":"ок","is_session_marker":false}"#.utf8))
        XCTAssertNil(old.blocks)
    }
}
