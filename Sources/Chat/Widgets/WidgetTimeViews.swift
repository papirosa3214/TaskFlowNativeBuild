import Foundation
import SwiftUI

// Три новых типа, где смысл — во времени: таймлайн по датам (Т3), календарная
// сетка (Т2) и тепловая карта плотности (Т5). Общий язык — `WidgetSemantics.swift`.
//
// Даты приходят строкой `ГГГГ-ММ-ДД`. Дата, которая не разобралась, НЕ
// превращается в сегодняшнюю: на её месте прочерк и подпись остаются
// (галерея §8.4) — иначе блок показывает правдоподобную, но выдуманную дату.

// MARK: - Т3. Таймлайн

/// «Что за чем и когда»: вертикальная ось с точками состояния. Отличие от
/// календарной сетки — не «что в этот день», а порядок и горизонт.
struct TimelineWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: data.string("title"), note: nil)
            let items = Array(data.array("items").prefix(6))
            if items.isEmpty {
                WidgetEmptyNote(text: "Дедлайнов нет")
            } else {
                TimelineAxisColumn(items: items, now: data.string("now"), ink: WidgetInk(scheme))
            }
            TimelinePastStrip(items: data.array("past"))
        }
    }
}

private struct TimelineAxisColumn: View {
    let items: [WidgetData]
    let now: String?
    let ink: WidgetInk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Отметка «сегодня» одна: перед первым пунктом, который сегодня
            // ещё не случился, а не перед каждым будущим.
            let todayIndex = items.firstIndex { isAfterToday($0) } ?? items.count
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let tone = WidgetTone(item.string("state"))
                if index == todayIndex {
                    TimelineTodayMark()
                }
                HStack(alignment: .top, spacing: TFSpacing.md) {
                    TimelineNode(tone: tone,
                                 showsTopLine: index > 0,
                                 showsBottomLine: index < items.count - 1)
                        .frame(maxHeight: .infinity)
                    TimelineItemText(item: item, tone: tone)
                }
            }
        }
    }

    private func isAfterToday(_ item: WidgetData) -> Bool {
        guard let now else { return false }
        guard let distance = WidgetFormat.days(from: now, to: item.string("date")) else { return false }
        return distance >= 0
    }
}

private struct TimelineNode: View {
    let tone: WidgetTone
    let showsTopLine: Bool
    let showsBottomLine: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(showsTopLine ? Color.tfStroke : Color.clear)
                .frame(width: 1, height: 8)
            Circle()
                .fill(tone.color)
                .overlay(Circle().strokeBorder(Color.tfCard, lineWidth: 2))
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(showsBottomLine ? Color.tfStroke : Color.clear)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 20, alignment: .center)
        .accessibilityHidden(true)
    }
}

private struct TimelineItemText: View {
    let item: WidgetData
    let tone: WidgetTone

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text(WidgetFormat.shortDate(item.string("date")))
                    .tfText(.micro)
                    .tfMonospaced(10)
                    .foregroundStyle(Color.tfDim)
                Spacer(minLength: 0)
                if let meta = item.string("meta") {
                    Text(meta)
                        .tfText(.caption)
                        .foregroundStyle(tone.color)
                        .lineLimit(1)
                }
            }
            Text(item.string("label") ?? "—")
                .tfText(.row)
                .foregroundStyle(Color.tfChatText)
                .lineLimit(2)
        }
        .padding(.bottom, TFSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WidgetFormat.shortDate(item.string("date"))), \(item.string("label") ?? "—"), \(tone.label)")
    }
}

private struct TimelineTodayMark: View {
    var body: some View {
        HStack(alignment: .center, spacing: TFSpacing.sm) {
            Rectangle()
                .fill(Color.tfBlue)
                .frame(height: 1)
            Text("сегодня")
                .tfText(.caption)
                .foregroundStyle(Color.tfBlue)
                .fixedSize()
        }
        .padding(.bottom, TFSpacing.xs)
        .accessibilityHidden(true)
    }
}

/// Прошедшие пункты — одной приглушённой строкой под осью, а не полноценными
/// строками: они уже случились и места в блоке не занимают.
private struct TimelinePastStrip: View {
    let items: [WidgetData]

    var body: some View {
        let visible = Array(items.prefix(3))
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: TFSpacing.xs) {
                        Image(systemName: "arrow.turn.down.right")
                            .tfTypeFont(size: TFIconSize.xs)
                        Text("\(WidgetFormat.shortDate(item.string("date"))) · \(item.string("label") ?? "—")")
                            .tfText(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.tfDim)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Т2. Календарная сетка

/// «Что в среду» сеткой: семь колонок, число событий в ячейке. Ни один из шести
/// действующих типов расположения по датам не показывает.
///
/// Переключение месяца свайпом в этом шаге НЕ сделано: блок приходит с данными
/// одного месяца, листать нечего, а пустая стрелка — тот же «элемент, который
/// ничего не делает», что запрещён галереей §7.4.
struct CalendarGridWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme

    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    /// Ячейка 32×32 (галерея §Т2), а не во всю ширину колонки: широкая
    /// «таблетка» пустого дня выглядит как заливка, а не как день.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(32), spacing: 6), count: 7)
    }

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: WidgetFormat.month(data.string("month")), note: data.string("title"))
            CalendarGridBody(data: data, weekdays: weekdays, columns: columns, ink: WidgetInk(scheme))
            // Пустая сетка осмысленна («в этом месяце ничего не было»), но без
            // подписи её не отличить от неотрисованного блока (галерея §Т2).
            if data.array("cells").isEmpty {
                WidgetEmptyNote(text: "Событий нет")
            }
        }
    }
}

private struct CalendarGridBody: View {
    let data: WidgetData
    let weekdays: [String]
    let columns: [GridItem]
    let ink: WidgetInk

    var body: some View {
        if let shape = WidgetFormat.monthShape(data.string("month"), firstWeekday: data.number("first_weekday") ?? 1) {
            grid(shape)
        } else {
            WidgetEmptyNote(text: "Месяц не разобран")
        }
    }

    private func grid(_ shape: (days: Int, leadingBlanks: Int)) -> some View {
        let today = data.string("today")
        let month = data.string("month")
        let trailing = max(0, 42 - shape.days - shape.leadingBlanks)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .tfText(.micro)
                    .foregroundStyle(Color.tfDim)
                    .frame(width: 32)
            }
            ForEach(0..<shape.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(width: 32, height: 32)
            }
            ForEach(1...max(shape.days, 1), id: \.self) { day in
                CalendarDayCell(day: day,
                                date: cellDate(month: month, day: day),
                                data: data,
                                isToday: today == cellDate(month: month, day: day),
                                ink: ink)
            }
            ForEach(0..<trailing, id: \.self) { _ in
                Color.clear.frame(width: 32, height: 32)
            }
        }
    }

    private func cellDate(month: String?, day: Int) -> String {
        "\(month ?? "")-\(String(format: "%02d", day))"
    }
}

private struct CalendarDayCell: View {
    let day: Int
    let date: String
    let data: WidgetData
    let isToday: Bool
    let ink: WidgetInk

    private var cell: WidgetData? {
        data.array("cells").first { $0.string("date") == date }
    }

    private var count: Int { Int((cell?.number("count") ?? 0).rounded()) }

    var body: some View {
        let tone = WidgetTone(cell?.string("tone"))
        Text(count > 0 ? WidgetFormat.integer(Double(count)) : "")
            .tfText(.caption)
            .tfMonospaced(11, weight: .medium)
            .foregroundStyle(count > 0 ? (tone == .over ? tone.color : Color.tfChatText) : Color.tfDim)
            .frame(width: 32, height: 32)
            .background(cell != nil && count > 0 ? ink.fill(tone) : ink.track,
                        in: RoundedRectangle(cornerRadius: TFRadius.md))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: TFRadius.md).strokeBorder(Color.tfStroke, lineWidth: 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayLabel)
    }

    private var dayLabel: String {
        var parts = ["\(day) число"]
        if let cell {
            let tone = WidgetTone(cell.string("tone"))
            parts.append("\(count) событий, \(tone.label)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Т5. Тепловая карта

/// Плотность за период. Единственный количественный признак — поэтому здесь
/// один тон на весь блок и пять ступеней заливки, а не категориальная палитра
/// (визуальный язык §1.5–1.6). Значение внутри ячейки не пишется: ячейка
/// слишком мала для текста.
struct HeatmapWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: data.string("title"), note: data.string("unit"))
            // Без ячеек карта молча рисует сетку нулей: владелец видит «пустую
            // карту», а это «в этом периоде ничего не было» (галерея §Т5).
            if data.array("cells").isEmpty {
                WidgetEmptyNote(text: "Активности не было")
            } else {
                HeatmapGrid(data: data, ink: WidgetInk(scheme))
                HeatmapLegend(data: data, ink: WidgetInk(scheme))
            }
        }
    }
}

private struct HeatmapGrid: View {
    let data: WidgetData
    let ink: WidgetInk

    /// 16 pt: при 16 неделях (предел контракта) сетка занимает 320 pt и влезает
    /// в блок на iPhone SE; при 22 pt она бы вылезла за карточку.
    private let cellSize: CGFloat = 16

    private var cells: [(column: Int, row: Int, value: Double)] {
        let parsed = data.array("cells").compactMap { cell -> (date: Date, value: Double)? in
            guard let date = WidgetFormat.date(cell.string("date")) else { return nil }
            return (date, max(0, cell.number("value") ?? 0))
        }
        guard let first = parsed.map(\.date).min() else { return [] }
        let firstWeekday = Int(WidgetFormat.clamped(data.number("first_weekday") ?? 1, 1, 7).rounded())
        let calendar = Calendar(identifier: .iso8601)
        func weekStart(_ date: Date) -> Date? {
            let weekday = calendar.component(.weekday, from: date)
            let iso = weekday == 1 ? 7 : weekday - 1
            let offset = (iso - firstWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date))
        }
        guard let anchor = weekStart(first) else { return [] }
        return parsed.compactMap { entry in
            guard let start = weekStart(entry.date) else { return nil }
            guard let column = calendar.dateComponents([.day], from: anchor, to: start).day else { return nil }
            let weekday = calendar.component(.weekday, from: entry.date)
            let row = (weekday == 1 ? 7 : weekday - 1) - firstWeekday + 1
            return (column / 7, max(0, row), entry.value)
        }
    }

    private var weeks: Int {
        let declared = Int((data.number("weeks") ?? 4).rounded())
        let byData = (cells.map(\.column).max() ?? 0) + 1
        return min(max(declared, byData), 16)
    }

    private var stepWidth: Double {
        max(1, data.number("max") ?? 1)
    }

    var body: some View {
        let byPosition = Dictionary(cells.map { ("\($0.column)-\($0.row)", $0.value) }, uniquingKeysWith: { first, _ in first })
        LazyHGrid(rows: Array(repeating: GridItem(.fixed(cellSize), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<(weeks * 7), id: \.self) { index in
                let column = index / 7
                let row = index % 7
                let value = byPosition["\(column)-\(row)"] ?? 0
                let step = Int((value / stepWidth * 4).rounded())
                RoundedRectangle(cornerRadius: TFRadius.pill)
                    .fill(ink.density(min(step, 4), base: Color.tfTeal))
                    .frame(width: cellSize, height: cellSize)
                    .accessibilityLabel("\(value) за день")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HeatmapLegend: View {
    let data: WidgetData
    let ink: WidgetInk

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0...4, id: \.self) { step in
                RoundedRectangle(cornerRadius: TFRadius.pill)
                    .fill(ink.density(step, base: Color.tfTeal))
                    .frame(width: TFIconSize.xs, height: TFIconSize.xs)
            }
            Text("больше")
                .tfText(.micro)
                .foregroundStyle(Color.tfDim)
            Spacer(minLength: TFSpacing.sm)
            Text(totalText)
                .tfText(.micro)
                .tfMonospaced(10)
                .foregroundStyle(Color.tfDim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Легенда плотности. \(totalText)")
    }

    private var totalText: String {
        let total = data.array("cells").reduce(0.0) { $0 + ($1.number("value") ?? 0) }
        let weeks = WidgetFormat.integer(data.number("weeks") ?? 0)
        return "всего \(WidgetFormat.integer(total)) за \(weeks) нед."
    }
}