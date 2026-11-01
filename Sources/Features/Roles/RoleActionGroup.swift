import SwiftUI

/// Кусок хода: реплика отдельно, а подряд идущие действия (шаги и
/// размышления) — одной группой.
enum RoleLiveSegment {
    case single(RoleChatLiveItem)
    case actions([RoleChatLiveItem])

    /// Группа — от двух действий подряд; одиночное действие остаётся строкой.
    ///
    /// `groupsSingleAction` — одиночное действие тоже полосой. Пока ход идёт,
    /// высота живого пузыря должна быть постоянной: полоса то появляется, то
    /// исчезает, а лента привязана к низу — и от этого она прыгает вверх-вниз
    /// (владелец 25.10.2026).
    static func split(_ items: [RoleChatLiveItem], grouping: Bool,
                      groupsSingleAction: Bool = false) -> [RoleLiveSegment] {
        guard grouping else { return items.map { .single($0) } }
        var result: [RoleLiveSegment] = []
        var run: [RoleChatLiveItem] = []
        func flush() {
            if run.count >= 2 || (groupsSingleAction && run.count == 1) {
                result.append(.actions(run))
            } else {
                result += run.map { .single($0) }
            }
            run = []
        }
        for item in items {
            if case .text = item { flush(); result.append(.single(item)) } else { run.append(item) }
        }
        flush()
        return result
    }
}

extension RoleLiveSegment {
    /// Идентичность сегмента в списке — по содержимому, а не по номеру.
    ///
    /// Номер менялся, как только в середину хода приходил текст: сегменты
    /// правее получали новые номера, `ForEach` пересоздавал их, у них заново
    /// шло появление (мигание строк) и сбрасывалось раскрытие блока — а
    /// раскрытое окошко размышлений это до 132 pt высоты (ревью ленты п.1.9).
    static func identities(_ segments: [RoleLiveSegment]) -> [String] {
        var textOrdinal = 0
        return segments.map { segment in
            switch segment {
            case .single(let item):
                if case .text = item {
                    textOrdinal += 1
                    return "text:\(textOrdinal)"
                }
                return "item:" + (item.actionID ?? item.id)
            case .actions(let items):
                return "actions:" + (items.first?.actionID ?? items.first?.id ?? "empty")
            }
        }
    }
}

/// Пачка действий роли одной строкой: «Действия  7 шагов · думал 1 мин ›»
/// (владелец 20.10.2026: «чтобы вся пачка инструментов фиксировалась под
/// одной полосой, щёлкнул — высветился весь перечень»). Пока ход идёт и пачка
/// последняя, под строкой виден текущий шаг.
struct RoleActionGroup<Row: View>: View {
    let items: [RoleChatLiveItem]
    let isLive: Bool
    /// Превью последнего действия под полосой — у каждой полосы, пока ход
    /// идёт. Полоса без превью и полоса с превью — разная высота, а лента
    /// привязана к низу: превью то появляется, то пропадает, и лента прыгает
    /// вверх-вниз (владелец 25.10.2026).
    var showsPreview = false
    @ViewBuilder let row: (RoleChatLiveItem) -> Row

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button {
                withAnimation(TFMotion.animation(TFMotion.standard, reduceMotion: reduceMotion)) { expanded.toggle() }
            } label: {
                header
                    .frame(maxWidth: .infinity, minHeight: TFHitTarget.min, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Действия роли: \(summary)")
            .accessibilityHint(expanded ? "Свернуть действия" : "Показать все действия")

            if expanded {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in row(item) }
                }
                .padding(.leading, TFSpacing.md)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.tfStroke).frame(width: 1)
                }
                .transition(.opacity)
            } else if (showsPreview || isLive), let last = items.last {
                row(last)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Image(systemName: "square.stack.3d.up")
                .tfTypeFont(size: 12, weight: .medium)
                .foregroundStyle(Color.tfDim)
                .frame(width: 16)
            if isLive {
                RoleShimmerText(text: "Работает")
            } else {
                Text("Действия").tfText(.meta).foregroundStyle(Color.tfSub)
            }
            Text(summary).tfText(.caption).foregroundStyle(Color.tfDim)
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .tfTypeFont(size: 10, weight: .semibold)
                .foregroundStyle(Color.tfDim)
        }
    }

    private var steps: Int {
        items.filter { if case .step = $0 { return true }; return false }.count
    }

    private var thinkingSeconds: Int {
        items.reduce(0) { sum, item in
            if case .thinking(let thinking) = item { return sum + (thinking.durationSeconds ?? 0) }
            return sum
        }
    }

    private var summary: String {
        var parts: [String] = []
        if steps > 0 { parts.append("\(steps) \(Self.plural(steps))") }
        if thinkingSeconds >= 1 { parts.append("думал \(RoleLiveFormat.duration(seconds: thinkingSeconds))") }
        return parts.joined(separator: " · ")
    }

    static func plural(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "шаг" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "шага" }
        return "шагов"
    }
}
