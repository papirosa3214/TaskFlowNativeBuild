import XCTest
@testable import TaskFlow

/// Разбор ответа роли на текст, таблицы, виджеты и артефакты (01.10.2026).
final class ChatRichContentTests: XCTestCase {
    func testTerminalWidgetWithoutClosingFenceDoesNotRemainLoading() {
        let text = "```widget\n{\"type\":\"card\",\"title\":\"Готово\"}"
        XCTAssertEqual(ChatRichContent.split(text), [.pending(.widget)])
        XCTAssertEqual(ChatRichContent.split(text, isStreaming: false), [.widget("{\"type\":\"card\",\"title\":\"Готово\"}")])
    }

    func testTerminalHTMLWithoutClosingFenceDoesNotRemainLoading() {
        let text = "```html\n<button>Готово</button>"
        XCTAssertEqual(ChatRichContent.split(text), [.pending(.html)])
        XCTAssertEqual(ChatRichContent.split(text, isStreaming: false), [.html("<button>Готово</button>")])
    }

    func testPlainMarkdownStaysOneSegment() {
        XCTAssertEqual(ChatRichContent.split("**Привет**\n\n- пункт"), [.markdown("**Привет**\n\n- пункт")])
    }

    func testTableWithAlignmentsBetweenText() {
        let text = """
        Сводка:

        | Роль | Задач | Статус |
        |:-----|------:|:------:|
        | QA | 3 | ок |
        | Архитектор | 12 |
        Итого — две роли.
        """
        let segments = ChatRichContent.split(text)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.first, .markdown("Сводка:\n"))
        guard case .table(let table) = segments[1] else { return XCTFail("ожидали таблицу") }
        XCTAssertEqual(table.header, ["Роль", "Задач", "Статус"])
        XCTAssertEqual(table.alignments, [.leading, .trailing, .center])
        XCTAssertEqual(table.rows, [["QA", "3", "ок"], ["Архитектор", "12", ""]])
        XCTAssertEqual(segments.last, .markdown("Итого — две роли."))
    }

    func testPipesInsideCodeBlockAreNotATable() {
        let text = "```\n| a | b |\n|---|---|\n```"
        XCTAssertEqual(ChatRichContent.split(text), [.markdown(text)])
    }

    func testWidgetAndHTMLBlocks() {
        let text = """
        Погода:
        ```widget
        {"type":"weather","temperature":12}
        ```
        ```html
        <button>Жми</button>
        ```
        """
        XCTAssertEqual(ChatRichContent.split(text), [
            .markdown("Погода:"),
            .widget(#"{"type":"weather","temperature":12}"#),
            .html("<button>Жми</button>"),
        ])
    }

    func testUnfinishedArtifactIsPendingWhileStreaming() {
        XCTAssertEqual(ChatRichContent.split("Сейчас соберу:\n```html\n<div>"), [
            .markdown("Сейчас соберу:"),
            .pending(.html),
        ])
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
