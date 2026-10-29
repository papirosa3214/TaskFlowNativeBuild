import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Разбор блока `widget` типа `table` в ответе роли (карточка 6556fa2d).
///
/// Сервер учит роли отдавать таблицу виджетом, а телефон такой виджет не
/// рисует: в переключателе типов виджета ветки `table` не было, и блок
/// уходил в текстовую заглушку. Тесты — на чистой модели без SwiftUI,
/// чтобы гоняться на маке без симулятора (`Tools/test_widget_table.py`).
final class WidgetTableTests: XCTestCase {
    // MARK: Обычные данные

    func testParsesColumnsAndRows() throws {
        let table = try parse(#"{"type":"table","columns":["Этап","Статус"],"rows":[["Сверка","Готово"],["Итог","В работе"]]}"#)
        XCTAssertEqual(table.columns, ["Этап", "Статус"])
        XCTAssertEqual(table.rows, [["Сверка", "Готово"], ["Итог", "В работе"]])
        XCTAssertEqual(table.totalRowCount, 2)
        XCTAssertFalse(table.isTruncated)
        XCTAssertNil(table.truncatedNote)
    }

    func testTitleIsOptional() throws {
        let withTitle = try parse(#"{"type":"table","title":"Сверка этапов","columns":["A"],"rows":[["1"]]}"#)
        XCTAssertEqual(withTitle.title, "Сверка этапов")
        let withoutTitle = try parse(#"{"type":"table","columns":["A"],"rows":[["1"]]}"#)
        XCTAssertNil(withoutTitle.title)
    }

    // MARK: Допуски по содержимому ячейки

    func testNumberCellBecomesText() throws {
        let table = try parse(#"{"type":"table","columns":["Кол-во","Доля"],"rows":[[42,1.5]]}"#)
        XCTAssertEqual(table.rows, [["42", "1.5"]])
    }

    func testBooleanCellBecomesYesOrNo() throws {
        let table = try parse(#"{"type":"table","columns":["Готово"],"rows":[[true],[false]]}"#)
        XCTAssertEqual(table.rows, [["да"], ["нет"]])
    }

    func testObjectCellBecomesCompactJSON() throws {
        let table = try parse(#"{"type":"table","columns":["Данные"],"rows":[[{"b":2,"a":1}]]}"#)
        XCTAssertEqual(table.rows, [["{\"a\":1,\"b\":2}"]])
    }

    func testListCellBecomesCompactJSON() throws {
        let table = try parse(#"{"type":"table","columns":["Список"],"rows":[[[1,"a"]]]}"#)
        XCTAssertEqual(table.rows, [["[1,\"a\"]"]])
    }

    func testNullCellBecomesEmptyText() throws {
        let table = try parse(#"{"type":"table","columns":["Пусто"],"rows":[[null]]}"#)
        XCTAssertEqual(table.rows, [[""]])
    }

    // MARK: Число ячеек в строке

    func testShortRowIsPaddedWithEmptyCells() throws {
        let table = try parse(#"{"type":"table","columns":["A","B","C"],"rows":[["1"]]}"#)
        XCTAssertEqual(table.rows, [["1", "", ""]])
    }

    func testLongRowIsTrimmed() throws {
        let table = try parse(#"{"type":"table","columns":["A","B"],"rows":[["1","2","3"]]}"#)
        XCTAssertEqual(table.rows, [["1", "2"]])
    }

    // MARK: Плохие данные

    func testMissingColumnsIsReported() {
        assertProblem(#"{"type":"table","rows":[["1"]]}"#, .missingColumns)
        assertProblem(#"{"type":"table","columns":[],"rows":[["1"]]}"#, .missingColumns)
    }

    func testMissingRowsIsReported() {
        assertProblem(#"{"type":"table","columns":["A"]}"#, .missingRows)
        assertProblem(#"{"type":"table","columns":["A"],"rows":[]}"#, .missingRows)
    }

    func testProblemNoteIsHonest() {
        XCTAssertEqual(WidgetTableProblem.missingColumns.note, "В таблице нет колонок")
        XCTAssertEqual(WidgetTableProblem.missingRows.note, "В таблице нет строк")
    }

    // MARK: Потолок строк

    func testRowsAboveLimitAreTruncatedWithHonestNote() throws {
        let rows = (1...250).map { #"["\#($0)"]"# }.joined(separator: ",")
        let table = try parse(#"{"type":"table","columns":["N"],"rows":[\#(rows)]}"#)
        XCTAssertEqual(table.rows.count, 200)
        XCTAssertEqual(table.rows.first, ["1"])
        XCTAssertEqual(table.rows.last, ["200"])
        XCTAssertEqual(table.totalRowCount, 250)
        XCTAssertTrue(table.isTruncated)
        XCTAssertEqual(table.truncatedNote, "Показаны первые 200 строк из 250")
    }

    func testTableAtLimitIsNotTruncated() throws {
        let rows = (1...200).map { #"["\#($0)"]"# }.joined(separator: ",")
        let table = try parse(#"{"type":"table","columns":["N"],"rows":[\#(rows)]}"#)
        XCTAssertEqual(table.rows.count, 200)
        XCTAssertFalse(table.isTruncated)
        XCTAssertNil(table.truncatedNote)
    }

    // MARK: Сводка запасного варианта

    func testFallbackSummaryNamesColumnsAndRows() throws {
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(#"{"type":"table","title":"Сверка","columns":["Этап","Статус"],"rows":[["a","b"],["c","d"]]}"#.utf8)
        ) as? [String: Any])
        XCTAssertEqual(WidgetTableParser.summary(raw), "Сверка — колонки: Этап, Статус — строк: 2")
    }

    func testFallbackSummaryIsEmptyWithoutAnyData() throws {
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(#"{"type":"table"}"#.utf8)
        ) as? [String: Any])
        XCTAssertNil(WidgetTableParser.summary(raw))
    }

    // MARK: Помощники

    private func parse(_ json: String) throws -> WidgetTable {
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        switch WidgetTableParser.parse(raw) {
        case .success(let table): return table
        case .failure(let problem): throw XCTSkip("Ожидалась таблица, а пришла проблема: \(problem)")
        }
    }

    private func assertProblem(_ json: String, _ expected: WidgetTableProblem, file: StaticString = #filePath, line: UInt = #line) {
        guard let raw = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            XCTFail("Нужен корректный JSON", file: file, line: line)
            return
        }
        switch WidgetTableParser.parse(raw) {
        case .success: XCTFail("Ожидалась проблема \(expected)", file: file, line: line)
        case .failure(let problem): XCTAssertEqual(problem, expected, file: file, line: line)
        }
    }
}
