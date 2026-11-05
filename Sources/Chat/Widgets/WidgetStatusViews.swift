import SwiftUI

// Четыре новых типа «про строку»: доска статусов, список с прогрессом у
// каждой строки, цепочка статусов и лестница шагов. Общий язык — тон, заливка
// и значок из `WidgetSemantics.swift`; здесь только геометрия.
//
// Все четыре ограничены по содержимому (галерея §3.4): первые пять элементов
// и строка «ещё N», блок не растёт выше 320 pt и не прокручивается внутри.

// MARK: - Т1. Доска статусов

/// Сводка по статусам: строка на статус с цветом, значком и долей. Отличие от
/// плиток `metrics` — силуэт строки и привязка цвета к смыслу, а не к категории.
struct StatusBoardWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: data.string("title"), note: data.string("note"))
            let groups = Array(data.array("groups").prefix(8))
            if groups.isEmpty {
                WidgetEmptyNote(text: "Данных пока нет")
            } else {
                StatusShareBar(groups: groups, ink: WidgetInk(scheme))
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        StatusRow(group: group, ink: WidgetInk(scheme))
                        if index < groups.count - 1 {
                            Divider().overlay(Color.tfStroke)
                        }
                    }
                }
            }
        }
    }
}

/// Полоса состава под заголовком: сегменты тона в порядке убывания доли.
private struct StatusShareBar: View {
    let groups: [WidgetData]
    let ink: WidgetInk

    private var segments: [(tone: WidgetTone, share: Double)] {
        groups.compactMap { group in
            guard let share = group.number("share"), share > 0 else { return nil }
            return (WidgetTone(group.string("tone")), WidgetFormat.clamped(share, 0, 100))
        }
    }

    var body: some View {
        if !segments.isEmpty {
            GeometryReader { geo in
                let total = max(segments.map(\.share).reduce(0, +), 0.001)
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(ink.fill(part.tone))
                            .frame(width: max(2, geo.size.width * part.share / total - 2))
                    }
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
    }
}

private struct StatusRow: View {
    let group: WidgetData
    let ink: WidgetInk

    var body: some View {
        let tone = WidgetTone(group.string("tone"))
        HStack(spacing: TFSpacing.md) {
            WidgetStateMark(tone: tone, ink: ink)
            Text(group.string("label") ?? "—")
                .tfText(.row)
                .foregroundStyle(Color.tfChatText)
                .lineLimit(2)
            Spacer(minLength: TFSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(WidgetFormat.integer(group.number("value") ?? 0))
                    .tfText(.row)
                    .tfMonospaced(14)
                    .foregroundStyle(Color.tfChatText)
                if let share = group.number("share") {
                    Text(WidgetFormat.percent(share / 100))
                        .tfText(.micro)
                        .tfMonospaced(10)
                        .foregroundStyle(Color.tfDim)
                }
            }
        }
        .frame(minHeight: TFHitTarget.min)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(tone: tone))
    }

    private func accessibilityText(tone: WidgetTone) -> String {
        let label = group.string("label") ?? "—"
        let value = WidgetFormat.integer(group.number("value") ?? 0)
        let share = group.number("share").map { ", \(WidgetFormat.percent($0 / 100))" } ?? ""
        return "\(label), \(tone.label), \(value)\(share)"
    }
}

// MARK: - Т8. Список с прогрессом у строки

/// Список, где у каждой строки своя доля: название сверху, полоса под ним,
/// справа дробь «3 из 12». Смысловая подсветка просрочки — единственное
/// место, где цвет используется как текст (§1.7, осознанное исключение).
struct BarsListWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: data.string("title"), note: data.string("note"))
            let items = Array(data.array("items").prefix(6))
            if items.isEmpty {
                WidgetEmptyNote(text: "Данных пока нет")
            } else {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        BarsListRow(item: item, ink: WidgetInk(scheme))
                    }
                }
            }
        }
    }
}

private struct BarsListRow: View {
    let item: WidgetData
    let ink: WidgetInk

    var body: some View {
        let tone = WidgetTone(item.string("tone"))
        let value = item.number("value") ?? 0
        let maxValue = max(item.number("max") ?? 0, 1)
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text(item.string("label") ?? "—")
                    .tfText(.row)
                    .foregroundStyle(Color.tfChatText)
                    .lineLimit(2)
                Spacer(minLength: TFSpacing.sm)
                if tone == .over {
                    Image(systemName: tone.icon)
                        .tfTypeFont(size: TFIconSize.xs)
                        .foregroundStyle(tone.color)
                }
                Text(fraction(item))
                    .tfText(.row)
                    .tfMonospaced(14)
                    .foregroundStyle(tone == .over ? tone.color : Color.tfSub)
            }
            WidgetBar(fraction: value / maxValue, fill: ink.fill(tone))
            if let meta = item.string("meta") {
                Text(meta)
                    .tfText(.micro)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fraction(_ item: WidgetData) -> String {
        let value = WidgetFormat.integer(item.number("value") ?? 0)
        let maxValue = item.number("max")
        guard let maxValue, maxValue > 0 else { return value }
        return "\(value) из \(WidgetFormat.integer(maxValue))"
    }
}

// MARK: - Т7. Цепочка статусов

/// Путь «приглашение → ответ → встреча»: дискретные звенья с соединителем.
/// Соединитель сплошной у пройденного и пунктирный у предстоящего — иначе
/// цепочка читается как список, а не как путь.
struct ChainWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme

    /// При шести звеньях на 360 pt подписи не влезают: показываем первые
    /// четыре и говорим сколько ещё (галерея §Т7).
    private let visibleLimit = 4

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: data.string("title"), note: data.string("summary"))
            let links = data.array("links")
            if links.isEmpty {
                WidgetEmptyNote(text: "Шагов нет")
            } else {
                ChainRow(links: Array(links.prefix(visibleLimit)), ink: WidgetInk(scheme))
                if links.count > visibleLimit {
                    Text("ещё \(links.count - visibleLimit)")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct ChainRow: View {
    let links: [WidgetData]
    let ink: WidgetInk

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                if index > 0 {
                    ChainConnector(passed: isPassed(links[index - 1]))
                }
                ChainLink(link: link, ink: ink)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func isPassed(_ link: WidgetData) -> Bool {
        WidgetTone(link.string("state")) == .done
    }
}

private struct ChainConnector: View {
    let passed: Bool

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 14))
            path.addLine(to: CGPoint(x: 10, y: 14))
        }
        .stroke(passed ? Color.tfStroke : Color.tfDim,
                style: StrokeStyle(lineWidth: 1, dash: passed ? [] : [3, 3]))
        .frame(width: 10, height: 28)
        .accessibilityHidden(true)
    }
}

private struct ChainLink: View {
    let link: WidgetData
    let ink: WidgetInk

    var body: some View {
        let tone = WidgetTone(link.string("state"))
        VStack(spacing: TFSpacing.xs) {
            ZStack {
                Circle().fill(ink.fill(tone))
                Image(systemName: tone.icon)
                    .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                    .foregroundStyle(Color.tfChatText)
            }
            .frame(width: 28, height: 28)
            Text(link.string("label") ?? "—")
                .tfText(.caption)
                .foregroundStyle(Color.tfChatText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let meta = link.string("meta") {
                Text(meta)
                    .tfText(.micro)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(link.string("label") ?? "—"), \(tone.label)")
    }
}

// MARK: - Т4. Лестница шагов

/// Этапы разной величины: высота ступени пропорциональна готовности, поэтому
/// «почти готово» и «начато» перестают выглядеть одинаково.
struct LadderWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: data.string("title"), note: nil)
            if let overall = data.number("overall") {
                LadderOverall(value: overall)
            }
            let steps = Array(data.array("steps").prefix(6))
            if steps.isEmpty {
                WidgetEmptyNote(text: "Шагов нет")
            } else {
                VStack(spacing: TFSpacing.sm) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        LadderStepRow(step: step, ink: WidgetInk(scheme))
                    }
                }
            }
        }
    }
}

private struct LadderOverall: View {
    let value: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Text(WidgetFormat.percent(value / 100))
                .tfText(.taskTitle)
                .tfMonospaced(20, weight: .semibold)
                .foregroundStyle(Color.tfChatText)
            Text("готность")
                .tfText(.micro)
                .foregroundStyle(Color.tfSub)
            Spacer(minLength: 0)
        }
    }
}

private struct LadderStepRow: View {
    let step: WidgetData
    let ink: WidgetInk

    var body: some View {
        let tone = WidgetTone(step.string("state"))
        let fraction = WidgetFormat.clamped((step.number("value") ?? 0) / 100, 0, 1)
        HStack(alignment: .center, spacing: TFSpacing.sm) {
            Text(step.string("label") ?? "—")
                .tfText(.row)
                .foregroundStyle(Color.tfChatText)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
            LadderStep(fraction: fraction, tone: tone, ink: ink)
                .frame(height: 28)
            Text(WidgetFormat.percent(fraction))
                .tfText(.row)
                .tfMonospaced(14)
                .foregroundStyle(Color.tfSub)
            if let note = step.string("note") {
                Text(note)
                    .tfText(.micro)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: TFHitTarget.min)
        .accessibilityElement(children: .combine)
    }
}

/// Ступень: трек во всю ширину, высота пропорциональна готовности (4…28),
/// заполненная часть — тоном состояния. Контур в обеих темах, чтобы нулевая
/// ступень не пропала.
private struct LadderStep: View {
    let fraction: Double
    let tone: WidgetTone
    let ink: WidgetInk

    var body: some View {
        GeometryReader { geo in
            let height = 4 + 24 * fraction
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: TFRadius.md).fill(ink.track)
                RoundedRectangle(cornerRadius: TFRadius.md)
                    .fill(ink.fill(tone))
                    .frame(width: max(2, geo.size.width * fraction))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}