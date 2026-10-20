import XCTest
import Foundation
@testable import TaskFlow

/// Один рисунок графика ответа роли во всём приложении — карточка 19f57bc9
/// (дефект критика 20.10.2026): блок графика рисовался дважды и разными
/// цветами, а путь «ответ роли в тексте поля» (результат шага, итог задачи)
/// читал точки только как `x`/`y`, поэтому график, написанный ролью по
/// формату каталога ролей (`label`/`value`), там не рисовался вовсе.
///
/// Файл читает исходники и проверяет разбор точек: он собирается и на коде
/// до правки, где правила о единственном рисунке падают.
final class RoleReplyChartTests: XCTestCase {

    // MARK: - Исходники

    private static var repoRoot: URL? {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo>
    }

    private func source(_ relativePath: String) throws -> String {
        let root = try XCTUnwrap(Self.repoRoot, "не найден корень репозитория рядом с Tests")
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func swiftSources() throws -> [String] {
        let root = try XCTUnwrap(Self.repoRoot)
        let sources = root.appendingPathComponent("Sources")
        var paths = (try? FileManager.default.subpathsOfDirectory(atPath: sources.path)) ?? []
        if paths.isEmpty, let walked = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) {
            paths = walked.compactMap { ($0 as? URL)?.path.replacingOccurrences(of: sources.path + "/", with: "") }
        }
        let result = paths.filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(result.count, 100, "Sources почти пуст — тест ничего не проверяет")
        return result
    }

    // MARK: - Правило 1. Рисунок графика один

    /// Оба пути показа ответа роли зовут один `RoleChartBlock`. Раньше
    /// `ChatStructuredOutputView` рисовал график сам teal, а `ChatWidgetView`
    /// — своим `ChartWidget` красным, и тот же ответ выглядел по-разному.
    func testBothPathsDrawChartByOneComponent() throws {
        for path in ["Sources/Features/Chat/ChatStructuredOutputView.swift",
                     "Sources/Features/Chat/ChatWidgetView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("RoleChartBlock("),
                          "\(path): график ответа роли должен рисоваться общим RoleChartBlock")
        }
    }

    /// Ни в одном файле показа ответа роли не осталось своей разметки графика.
    func testNoChartMarksOutsideSharedComponent() throws {
        let shared = "Sources/Features/Chat/RoleChartBlock.swift"
        let offenders = try swiftSources()
            .filter { $0 != shared }
            .filter { path in
                let text = (try? String(contentsOf: Self.repoRoot!.appendingPathComponent(path), encoding: .utf8)) ?? ""
                return text.contains("BarMark(") || text.contains("LineMark(")
            }
        XCTAssertEqual(offenders, [],
                       "Свой рисунок графика остался в: \(offenders.joined(separator: ", ")). "
                        + "График ответа роли рисует только RoleChartBlock")
    }

    /// Цвет графика один: teal из общего компонента, а не красный виджета.
    func testChartColorIsShared() throws {
        let widget = try source("Sources/Features/Chat/ChatWidgetView.swift")
        XCTAssertFalse(widget.contains("tfRed.gradient"),
                       "Блок графика виджета снова красится своим цветом")
        let bars = try source("Sources/Features/Chat/Widgets/WidgetLayoutVariants.swift")
        XCTAssertTrue(bars.contains("RoleChartBlock.ink"),
                      "Полосы блока графика должны тем же цветом, что и график")
    }

    // MARK: - Правило 2. Точки графика читаются в обоих форматах

    /// Формат каталога ролей: `label`/`value`.
    func testChartPointsFromCatalogFormat() throws {
        let data = try XCTUnwrap(WidgetData.parse("""
        {"points":[{"label":"Пн","value":4},{"label":"Вт","value":7}]}
        """))
        let points = data.roleChartPoints()
        XCTAssertEqual(points.map(\.label), ["Пн", "Вт"])
        XCTAssertEqual(points.map(\.value), [4, 7])
    }

    /// Старый блок ```widget: `x`/`y`. Тот же список точек, тот же результат.
    func testChartPointsFromLegacyWidgetFormat() throws {
        let data = try XCTUnwrap(WidgetData.parse("""
        {"points":[{"x":"Пн","y":4},{"x":"Вт","y":7}]}
        """))
        let points = data.roleChartPoints()
        XCTAssertEqual(points.map(\.label), ["Пн", "Вт"])
        XCTAssertEqual(points.map(\.value), [4, 7])
    }

    /// Точка без значения не рисуется: пустой график хуже, чем точка без числа.
    func testChartPointWithoutValueIsSkipped() throws {
        let data = try XCTUnwrap(WidgetData.parse("""
        {"points":[{"label":"Пн","value":4},{"label":"Вт"},{"label":"Ср","value":"2,5"}]}
        """))
        let points = data.roleChartPoints()
        XCTAssertEqual(points.map(\.label), ["Пн", "Ср"])
        XCTAssertEqual(points.map(\.value), [4, 2.5], "Число строкой тоже читается — так пишут роли")
    }
}
