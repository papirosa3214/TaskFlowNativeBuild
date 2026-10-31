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

    /// Все исходники приложения путями ОТ КОРНЯ репозитория (`Sources/...`).
    ///
    /// Раньше здесь возвращались пути относительно `Sources/`, а читались они
    /// от корня репозитория — `try?` молча отдавал пустую строку, и сторож
    /// проходил вхолостую, ни разу не открыв файл. Теперь путь и место чтения
    /// совпадают, а число найденных файлов проверяется (см. `RoleReplyRenderTests`).
    private func repoSwiftSources() throws -> [String] {
        let root = try XCTUnwrap(Self.repoRoot)
        let sources = root.appendingPathComponent("Sources")
        var paths = (try? FileManager.default.subpathsOfDirectory(atPath: sources.path)) ?? []
        if paths.isEmpty, let walked = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) {
            paths = walked.compactMap { ($0 as? URL)?.path.replacingOccurrences(of: sources.path + "/", with: "") }
        }
        let result = paths.filter { $0.hasSuffix(".swift") }.map { "Sources/" + $0 }.sorted()
        XCTAssertGreaterThan(result.count, 100, "Sources почти пуст — тест ничего не проверяет")
        return result
    }

    // MARK: - Правило 1. Рисунок графика один

    /// Оба пути показа ответа роли зовут один `RoleChartBlock`. Раньше
    /// `ChatStructuredOutputView` рисовал график сам teal, а `ChatWidgetView`
    /// — своим `ChartWidget` красным, и тот же ответ выглядел по-разному.
    func testBothPathsDrawChartByOneComponent() throws {
        for path in ["Sources/Chat/Output/ChatStructuredOutputView.swift",
                     "Sources/Chat/Output/ChatWidgetView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("RoleChartBlock("),
                          "\(path): график ответа роли должен рисоваться общим RoleChartBlock")
        }
    }

    /// Файлы, где показывают ответ роли. Именно они обязаны рисовать график
    /// общим `RoleChartBlock` и не могут заводить свою разметку графика.
    ///
    /// Набор задан явно, а не «все файлы с `BarMark(`»: график активности в
    /// `Sources/Features/Activity/AIUsageScreen.swift` — законный, это статистика
    /// активности, а не ответ роли.
    private static let roleReplyFiles = [
        "Sources/Chat/Output/ChatStructuredOutputView.swift",
        "Sources/Chat/Output/ChatWidgetView.swift",
        "Sources/Chat/Widgets/WidgetLayoutVariants.swift",
    ]

    /// Общий компонент графика ответа роли — единственное место, где разметка
    /// графика (`BarMark`/`LineMark`) разрешена.
    private static let sharedChartComponent = "Sources/Chat/Output/RoleChartBlock.swift"

    /// Ни в одном файле показа ответа роли не осталось своей разметки графика.
    func testNoChartMarksOutsideSharedComponent() throws {
        let root = try XCTUnwrap(Self.repoRoot, "не найден корень репозитория рядом с Tests")

        // Файлы показа ответа роли — те, что зовут общий компонент. Список
        // вычисляется по диску, поэтому новый экран с ответом роли попадает
        // в проверку сам.
        let roleReplyFiles = try repoSwiftSources()
            .filter { $0 != Self.sharedChartComponent }
            .filter { path in
                let text = (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
                return text.contains("RoleChartBlock")
            }

        // Канонические файлы должны быть среди найденных: иначе набор
        // «файлов, где показывают ответ роли» пуст и проверка ничего не видит.
        for path in Self.roleReplyFiles {
            XCTAssertTrue(roleReplyFiles.contains(path),
                          "\(path): файл показа ответа роли не найден — проверяемый набор пуст")
        }

        var read = 0
        var offenders: [String] = []
        for path in roleReplyFiles {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            read += 1
            if text.contains("BarMark(") || text.contains("LineMark(") {
                offenders.append(path)
            }
        }
        // Сторож не должен проходить вхолостую: пустой или слишком короткий
        // набор прочитанных файлов — это сломанный путь, а не «нарушений нет».
        XCTAssertGreaterThanOrEqual(read, Self.roleReplyFiles.count,
                                     "прочитано слишком мало файлов — проверка ничего не проверяет")
        XCTAssertEqual(offenders, [],
                       "Свой рисунок графика остался в: \(offenders.joined(separator: ", ")). "
                        + "График ответа роли рисует только RoleChartBlock")
    }

    /// Цвет графика один: teal из общего компонента, а не красный виджета.
    func testChartColorIsShared() throws {
        let widget = try source("Sources/Chat/Output/ChatWidgetView.swift")
        XCTAssertFalse(widget.contains("tfRed.gradient"),
                       "Блок графика виджета снова красится своим цветом")
        let bars = try source("Sources/Chat/Widgets/WidgetLayoutVariants.swift")
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
