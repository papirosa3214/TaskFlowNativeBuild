import XCTest
@testable import TaskFlow

final class NoteDocumentSerializationTests: XCTestCase {
    func testBulletListStopsBeforeTableHeadingAndParagraph() throws {
        let markdown = """
        # Карта сервера

        - Проверенный сервис

        ## Проекты

        | Проект | Порт |
        | --- | --- |
        | TaskFlow | 3001 |

        Описание после таблицы
        """
        let original = NoteDocument(blocks: MarkdownParser.parse(markdown))
        let encoded = original.encodeToJSONString()
        let decoded = NoteDocument.decode(fromJSONString: encoded)

        assertSameContent(decoded, original)
        let data = try XCTUnwrap(encoded.data(using: .utf8))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = try XCTUnwrap(document["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { $0["type"] as? String }, ["heading", "bulletList", "heading", "table", "paragraph"])
    }

    func testNestedListStopsBeforeFollowingTable() {
        let markdown = """
        - Сервис
          - Проверка

        | Модель | Устройство |
        | --- | --- |
        | BGE-M3 | GPU |

        - Следующий список
        """
        let original = NoteDocument(blocks: MarkdownParser.parse(markdown))
        let decoded = NoteDocument.decode(fromJSONString: original.encodeToJSONString())

        assertSameContent(decoded, original)
    }

    func testAllListKindsPreserveFollowingNonListBlocks() {
        let followingBlocks: [NoteBlock] = [
            NoteBlock(kind: .paragraph, runs: [RichRun(text: "Сохранить абзац")]),
            NoteBlock(kind: .heading(level: 2), runs: [RichRun(text: "Сохранить заголовок")]),
            NoteBlock(kind: .horizontalRule),
            NoteBlock(kind: .codeBlock(language: "sh"), runs: [RichRun(text: "echo test")]),
            NoteBlock(kind: .blockquote, runs: [RichRun(text: "Сохранить цитату")]),
        ]
        for listKind in [BlockKind.bulletItem, .orderedItem, .taskItem(checked: true)] {
            let original = NoteDocument(blocks: [NoteBlock(kind: listKind, runs: [RichRun(text: "Пункт")])] + followingBlocks)
            assertSameContent(NoteDocument.decode(fromJSONString: original.encodeToJSONString()), original)
        }
    }

    private func assertSameContent(_ actual: NoteDocument, _ expected: NoteDocument, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.blocks.map(\.kind), expected.blocks.map(\.kind), file: file, line: line)
        XCTAssertEqual(actual.blocks.map(\.level), expected.blocks.map(\.level), file: file, line: line)
        XCTAssertEqual(actual.blocks.map(\.runs), expected.blocks.map(\.runs), file: file, line: line)
    }
}
