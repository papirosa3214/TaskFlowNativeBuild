import Foundation

/// Таблица в виджете ответа роли (карточка 6556fa2d).
///
/// Сервер учит роль отдавать таблицу виджетом, а телефон такой виджет не
/// рисовал: в переключателе типов виджета ветки `table` не было, и блок
/// уходил в текстовую заглушку «Виджет этого типа пока не рисуется».
///
/// Модель и разбор живут здесь, без SwiftUI: их можно собрать и прогнать на
/// маке обычным `swiftc` (`Tools/test_widget_table.py`), без симулятора.
/// Рисует таблицу `ChatTableView` — тот же компонент, что и markdown-таблица
/// в тексте ответа, поэтому одна и та же таблица выглядит одинаково.
struct WidgetTable: Equatable {
    /// Заголовок над таблицей — необязательный.
    var title: String?
    /// Шапка таблицы.
    var columns: [String]
    /// Строки, приведённые к числу колонок.
    var rows: [[String]]
    /// Сколько строк прислала роль: может быть больше, чем нарисовано.
    var totalRowCount: Int
    /// true — часть строк не показана (см. `truncatedNote`).
    var isTruncated: Bool
    /// Честная подпись о неполных данных.
    var truncatedNote: String?
}

/// Плохие данные виджета-таблицы: рисовать нечего — говорим, чего не хватает.
enum WidgetTableProblem: Equatable, Error {
    case missingColumns
    case missingRows

    /// Подпись для владельца — что именно сломалось в данных.
    var note: String {
        switch self {
        case .missingColumns: return "В таблице нет колонок"
        case .missingRows: return "В таблице нет строк"
        }
    }
}

/// Разбор блока `widget` типа `table` в словарь виджета.
enum WidgetTableParser {
    /// Больше строк не рисуем: список строк телефон строит целиком, а роль
    /// может прислать таблицу на сотни строк.
    static let maxRows = 200

    /// Разбор по правилам контракта: колонки обязательны, строки обязательны,
    /// ячейка приводится к строке, лишние ячейки отбрасываются, недостающие —
    /// дополняются пустыми.
    static func parse(_ raw: [String: Any]) -> Result<WidgetTable, WidgetTableProblem> {
        let columns = columnTexts(raw)
        guard !columns.isEmpty else { return .failure(.missingColumns) }

        let rowValues = raw["rows"] as? [Any] ?? []
        guard !rowValues.isEmpty else { return .failure(.missingRows) }

        let shown = rowValues.prefix(maxRows).map { row -> [String] in
            // Строка должна быть массивом; иначе не теряем её, а кладём
            // одним значением — так данные не пропадают молча.
            let cells = (row as? [Any]) ?? [row]
            let values = cells.map(cellText)
            guard values.count < columns.count else { return Array(values.prefix(columns.count)) }
            return values + Array(repeating: "", count: columns.count - values.count)
        }

        let isTruncated = rowValues.count > shown.count
        return .success(WidgetTable(
            title: titleText(raw),
            columns: columns,
            rows: shown,
            totalRowCount: rowValues.count,
            isTruncated: isTruncated,
            truncatedNote: isTruncated ? "Показаны первые \(maxRows) строк из \(rowValues.count)" : nil
        ))
    }

    /// Короткая текстовая сводка о таблице — для запасного варианта, когда
    /// таблицу рисовать нечем (например, пришли данные без колонок).
    static func summary(_ raw: [String: Any]) -> String? {
        let columns = columnTexts(raw)
        let rows = raw["rows"] as? [Any] ?? []
        var parts: [String] = []
        if let title = titleText(raw) { parts.append(title) }
        if !columns.isEmpty { parts.append("колонки: " + columns.joined(separator: ", ")) }
        if !rows.isEmpty { parts.append("строк: \(rows.count)") }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    // MARK: - Значения

    private static func titleText(_ raw: [String: Any]) -> String? {
        guard let title = raw["title"] as? String else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func columnTexts(_ raw: [String: Any]) -> [String] {
        (raw["columns"] as? [Any])?.map(cellText) ?? []
    }

    /// Ячейка — строка. Число и «да/нет» приводятся к строке, объект и список
    /// показываются компактным JSON, чтобы данные не потерялись молча.
    static func cellText(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let number = value as? NSNumber {
            // Настоящее «да/нет» отличается от числа 0/1 по типу CFBoolean.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "да" : "нет"
            }
            return format(number.doubleValue)
        }
        if let text = value as? String { return text }
        if let array = value as? [Any] { return jsonText(array) }
        if let object = value as? [String: Any] { return jsonText(object) }
        return String(describing: value)
    }

    /// Число без хвостов: целое — без дробной части, дробное — одна цифра
    /// после запятой (как в остальных виджетах приложения).
    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func jsonText(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return text
    }
}
