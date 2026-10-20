import Charts
import SwiftUI

/// Точка графика ответа роли в одном виде для обоих путей.
///
/// Формат каталога ролей (сервер, `widgetContract.ts`) — `label`/`value`,
/// старый блок ```widget — `x`/`y`. Раньше каждый путь читал свой формат:
/// график по каталогу в результате шага и в итоге задачи не рисовался вовсе,
/// а в чате и комментарии рисовался teal, в блоке виджета — красным, то есть
/// один и тот же ответ роли выглядел по-разному в зависимости от экрана
/// (карточка 19f57bc9, дефект критика 20.10.2026).
struct RoleChartPoint: Identifiable, Equatable {
    let id: Int
    let label: String
    let value: Double
}

/// Единственный рисунок графика ответа роли во всём приложении: и блок
/// конверта (`ChatStructuredOutputView`), и блок ```widget
/// (`ChatWidgetView`) рисуются им. Цвет, высота, подпись оси и accessibility
/// — одни и те же, поэтому вид графика не может разойтись по экранам.
struct RoleChartBlock: View {
    let title: String?
    let kind: String?
    let unit: String?
    let points: [RoleChartPoint]
    /// Идентификатор для тестов. У блока конверта он прежний
    /// (`chat.structured-output.chart`) — на него завязаны UI-тесты другой
    /// карточки, менять их из-за сведения двух рисунков не нужно.
    var accessibilityId: String = "role.chart"

    /// Один цвет всех графиков ответа роли. Раньше их было два: teal в
    /// конверте и красный в блоке виджета.
    static let ink = Color.tfTeal

    private var isLine: Bool { kind?.lowercased() == "line" }

    var body: some View {
        WidgetCard(title: title) {
            Chart(points) { point in
                if isLine {
                    LineMark(x: .value("Метка", point.label), y: .value("Значение", point.value))
                        .foregroundStyle(Self.ink)
                    PointMark(x: .value("Метка", point.label), y: .value("Значение", point.value))
                        .foregroundStyle(Self.ink)
                } else {
                    BarMark(x: .value("Метка", point.label), y: .value("Значение", point.value))
                        .foregroundStyle(Self.ink.gradient)
                        .cornerRadius(4)
                }
            }
            .chartYAxisLabel(unit ?? "")
            .frame(height: 180)
            .accessibilityLabel(accessibilityLabel)
        }
        .accessibilityIdentifier(accessibilityId)
    }

    private var accessibilityLabel: Text {
        let summary = points
            .map { "\($0.label): \($0.value.rounded() == $0.value ? String(Int($0.value)) : String($0.value))" }
            .joined(separator: ", ")
        return Text([title, summary, unit].compactMap { $0 }.joined(separator: ". "))
    }
}

extension WidgetData {
    /// Точки графика в обоих форматах: `label`/`value` каталога ролей и
    /// `x`/`y` старого блока виджета. Без метки — порядковый номер, как раньше.
    func roleChartPoints(_ key: String = "points") -> [RoleChartPoint] {
        array(key).enumerated().compactMap { index, item in
            guard let value = item.number("value") ?? item.number("y") else { return nil }
            return RoleChartPoint(id: index,
                                  label: item.string("label") ?? item.string("x") ?? "\(index + 1)",
                                  value: value)
        }
    }
}
