import SwiftUI

// Шесть компоновок К1–К6 из галереи (`docs/2026-10-14-widget-gallery-layouts-and-types.md`,
// раздел 4). Это НЕ новые типы: те же шесть действующих типов, нарисованные
// иначе, потому что блок принёс новые поля. Старые блоки без новых полей
// рисуются ровно как раньше — ветки включаются по наличию полей, а не флагом.
//
// Общий признак всех шести: силуэт и ведущий элемент отличаются от обычного
// вида типа, поэтому подпись блока перестаёт быть единственным различием.

// MARK: - К1. Плитки со смысловым цветом и иконкой

/// `metrics` с полями `tone`/`icon`: статус виден без чтения подписи.
struct MetricsTilesWidget: View {
    let items: [WidgetData]
    @Environment(\.colorScheme) private var scheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: TFSpacing.md), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: TFSpacing.md) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                MetricsTile(item: item, ink: WidgetInk(scheme))
            }
        }
    }
}

private struct MetricsTile: View {
    let item: WidgetData
    let ink: WidgetInk

    var body: some View {
        let tone = WidgetTone(item.string("tone"))
        HStack(alignment: .center, spacing: TFSpacing.sm) {
            WidgetStateMark(tone: tone, ink: ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.string("label") ?? "")
                    .tfText(.micro)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(2)
                Text(item.string("value") ?? "—")
                    .tfText(.taskTitle)
                    .tfMonospaced(20, weight: .semibold)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                MetricsDelta(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.fill(tone), in: RoundedRectangle(cornerRadius: TFRadius.lg))
        .accessibilityElement(children: .combine)
    }
}

/// Дельта нужна только К1: в обычных плитках она уже нарисована.
private struct MetricsDelta: View {
    let item: WidgetData

    var body: some View {
        if let delta = item.string("delta") {
            let trend = item.string("trend") ?? ""
            Label(delta, systemImage: trend == "up" ? "arrow.up.right"
                  : trend == "down" ? "arrow.down.right" : "arrow.right")
                .tfText(.micro)
                .foregroundStyle(trend == "up" ? Color.tfGreen
                                 : trend == "down" ? Color.tfRed : Color.tfSub)
        }
    }
}

// MARK: - К2. Строки со статусом и прогрессом справа

/// `checklist` с полями `tone`/`meta`/`progress`: у пункта появляется статус и
/// вторичная величина справа, поэтому строка перестаёт быть просто пунктом.
struct ChecklistRowsWidget: View {
    let items: [WidgetData]
    /// nil — виджет вне переписки: отметка локальная (галерея, превью).
    var binding: ChatWidgetView.ChecklistBinding?
    @Environment(\.colorScheme) private var scheme
    @State private var toggled: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                ChecklistStatusRow(item: item,
                                   ink: WidgetInk(scheme),
                                   isDone: isDone(index: index, item: item),
                                   toggle: { toggle(index: index, item: item) })
            }
            ChecklistSyncNotice(failure: binding?.failure())
        }
    }

    /// В переписке — по состоянию сообщения с сервера, иначе по-старому,
    /// локально (галерея виджетов, превью).
    private func isDone(index: Int, item: WidgetData) -> Bool {
        if let binding { return binding.isDone(index, item) }
        return ((item.bool("done") ?? false) != toggled.contains(index))
    }

    private func toggle(index: Int, item: WidgetData) {
        guard let binding else {
            withAnimation(.snappy(duration: TFDuration.base)) {
                if toggled.contains(index) { toggled.remove(index) } else { toggled.insert(index) }
            }
            return
        }
        binding.toggle(index, item)
    }
}

private struct ChecklistStatusRow: View {
    let item: WidgetData
    let ink: WidgetInk
    let isDone: Bool
    let toggle: () -> Void

    var body: some View {
        let tone = isDone ? WidgetTone.done : WidgetTone(item.string("tone"))
        Button(action: toggle) {
            HStack(spacing: TFSpacing.md) {
                WidgetStateMark(tone: tone, ink: ink)
                Text(item.string("text") ?? "")
                    .tfText(.row)
                    .foregroundStyle(isDone ? Color.tfSub : Color.tfText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let meta = item.string("meta") {
                    HStack(spacing: 4) {
                        Image(systemName: tone.icon)
                            .font(.system(size: TFIconSize.xs))
                        Text(meta).tfText(.caption)
                    }
                    .foregroundStyle(tone.color)
                    .fixedSize()
                }
                if let progress = item.number("progress") {
                    WidgetBar(fraction: WidgetFormat.clamped(progress / 100, 0, 1),
                              fill: ink.fill(tone),
                              height: 4)
                        .frame(width: 44)
                }
            }
            .frame(minHeight: TFHitTarget.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.string("text") ?? ""), \(tone.label)\(isDone ? ", свёрнуто" : "")")
    }
}

// MARK: - К3. Горизонтальные полосы

/// `chart` с `layout: bars`: длинные названия категорий больше не режутся под
/// углом вертикального столбика. Значение печатается рядом с подписью, не на
/// полосе — на заливке своего цвета текст не проходит контраст (§1.7).
struct ChartBarsWidget: View {
    let points: [ChartBarPoint]

    private func peak(in points: [ChartBarPoint]) -> Double {
        points.map(\.value).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                ChartBarRow(point: point, peak: peak(in: points))
            }
        }
    }
}

struct ChartBarPoint: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

private struct ChartBarRow: View {
    let point: ChartBarPoint
    /// Максимум набора: у полосы нет своей оси, поэтому доля считается от него.
    let peak: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text(point.label)
                    .tfText(.row)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: TFSpacing.sm)
                Text(WidgetFormat.integer(point.value))
                    .tfText(.row)
                    .tfMonospaced(14)
                    .foregroundStyle(Color.tfText)
            }
            WidgetBar(fraction: fraction, fill: Color.tfRed.opacity(scheme == .dark ? 0.18 : 0.25), height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    /// Доля от максимума набора, а не от единицы: у полосы нет своей оси.
    private var fraction: Double {
        WidgetFormat.clamped(point.value / max(peak, 0.001), 0, 1)
    }
}

// MARK: - К4. Шкала с делениями и вехой

/// `progress` с полем `milestone`: по шкале видно, где цель, а не только
/// «сколько процентов».
struct ProgressMilestoneWidget: View {
    let items: [WidgetData]
    let milestone: WidgetData?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                ProgressMilestoneRow(item: item)
            }
            if let milestone {
                ProgressScale(milestone: milestone, ink: WidgetInk(scheme))
                    .padding(.top, TFSpacing.xs)
            }
        }
    }
}

private struct ProgressMilestoneRow: View {
    let item: WidgetData

    var body: some View {
        let fraction = fractionOf(item)
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack {
                Text(item.string("label") ?? "")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Spacer(minLength: TFSpacing.sm)
                Text(WidgetFormat.percent(fraction))
                    .tfText(.row)
                    .tfMonospaced(14)
                    .foregroundStyle(Color.tfSub)
            }
            WidgetBar(fraction: fraction,
                      fill: fraction >= 1 ? Color.tfGreen : Color.tfBlue,
                      height: 8)
            if let note = item.string("note") {
                Text(note).tfText(.caption).foregroundStyle(Color.tfSub).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fractionOf(_ item: WidgetData) -> Double {
        let raw = item.number("value") ?? 0
        return WidgetFormat.clamped(raw > 1 ? raw / 100 : raw, 0, 1)
    }
}

/// Полоса 8 pt с делениями в 25 % и ромбом вехи.
private struct ProgressScale: View {
    let milestone: WidgetData
    let ink: WidgetInk

    private var at: Double {
        WidgetFormat.clamped((milestone.number("at") ?? 0) / 100, 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.track).frame(height: 8)
                    Capsule().fill(ink.fill(.done)).frame(width: geo.size.width * at, height: 8)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: -3))
                        path.addLine(to: CGPoint(x: 6, y: 4))
                        path.addLine(to: CGPoint(x: 12, y: -3))
                    }
                    .fill(Color.tfPurple)
                    .position(x: geo.size.width * at, y: 6)
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { step in
                        Rectangle()
                            .fill(Color.tfStroke)
                            .frame(width: 1, height: 4)
                            .position(x: geo.size.width * step, y: -8)
                    }
                }
            }
            .frame(height: 28)
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text(milestone.string("label") ?? "Веха")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                if let date = milestone.string("date") {
                    Text(date).tfText(.caption).foregroundStyle(Color.tfDim)
                }
                Spacer(minLength: 0)
                Text(WidgetFormat.percent(at)).tfText(.caption).foregroundStyle(Color.tfPurple)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Веха \(milestone.string("label") ?? ""), \(WidgetFormat.percent(at))")
    }
}

// MARK: - К5. Лента статуса карточки

/// `card` с полем `tone`: статус читается до чтения текста. Лента повторяет
/// верхние углы карточки, поэтому рисуется как верхняя кромка самого блока.
struct WidgetToneRibbon: View {
    let tone: WidgetTone

    var body: some View {
        Rectangle()
            .fill(tone.color)
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - К6. Одна горизонтальная лента чисел

/// `metrics` с `layout: strip`: короткая сводка из трёх чисел одной строкой.
/// Четыре числа в ряд на телефоне не читаются — три в ряд читаются.
struct MetricsStripWidget: View {
    let items: [WidgetData]

    /// Столько чисел в ряд: четыре на телефоне не читаются, три читаются.
    /// Больше трёх значений переносится на следующую строку, а не сжимается.
    private let perRow = 3

    private var rows: [[WidgetData]] {
        stride(from: 0, to: items.count, by: perRow).map { start in
            Array(items[start..<min(start + perRow, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: TFSpacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, chunk in
                HStack(spacing: TFSpacing.sm) {
                    ForEach(Array(chunk.enumerated()), id: \.offset) { index, item in
                        MetricsStripCell(item: item)
                        if index < chunk.count - 1 {
                            Rectangle()
                                .fill(Color.tfStroke)
                                .frame(width: 1, height: 30)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MetricsStripCell: View {
    let item: WidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.string("value") ?? "—")
                .tfText(.taskTitle)
                .tfMonospaced(20, weight: .semibold)
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
            Text(item.string("label") ?? "")
                .tfText(.micro)
                .foregroundStyle(Color.tfDim)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

