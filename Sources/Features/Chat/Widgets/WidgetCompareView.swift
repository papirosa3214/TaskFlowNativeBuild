import SwiftUI

// Сравнение двух значений (новый тип Т6). Смысл типа — разница, поэтому разница
// и стоит в центре: два значения симметрично, полоса под ними и вердикт словами.
//
// Отличие от `metrics`: там четыре плитки, где дельта стоит рядом со своим
// числом и теряется; здесь ровно две величины и одна мысль между ними.
struct CompareWidget: View {
    let data: WidgetData
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private var leftValue: Double? { data.object("left")?.number("value") }
    private var rightValue: Double? { data.object("right")?.number("value") }

    var body: some View {
        WidgetCard(title: nil) {
            WidgetTitle(title: data.string("title"), note: data.string("subject"))
            if leftValue == nil || rightValue == nil {
                WidgetEmptyNote(text: "Данных пока нет")
            } else {
                CompareSide(side: data.object("left"), unit: data.string("unit"), isCheaper: isCheaper(.left)) { open(side: data.object("left")) }
                Divider().overlay(Color.tfStroke)
                CompareSide(side: data.object("right"), unit: data.string("unit"), isCheaper: isCheaper(.right)) { open(side: data.object("right")) }
                if let leftValue, let rightValue {
                    CompareDifferenceBar(left: leftValue, right: rightValue, ink: WidgetInk(scheme))
                }
                if let verdict = data.string("verdict") {
                    // Вердикт — обычным цветом текста, не зелёным: насыщенный зелёный
                    // текст в тёмной теме проходит контраст только крупным (§1.7).
                    Text(verdict)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                }
            }
        }
    }

    private enum Side { case left, right }

    private func isCheaper(_ side: Side) -> Bool {
        guard let leftValue, let rightValue, leftValue != rightValue else { return false }
        switch side {
        case .left: return leftValue < rightValue
        case .right: return rightValue < leftValue
        }
    }

    /// Ссылка открывается только по контракту — `https`. Любая другая схема
    /// игнорируется: блок приходит из ответа роли, доверять его схеме нельзя.
    private func open(side: WidgetData?) {
        guard let raw = side?.string("link"), raw.lowercased().hasPrefix("https://"),
              let url = URL(string: raw) else { return }
        openURL(url)
    }
}

private struct CompareSide: View {
    let side: WidgetData?
    let unit: String?
    let isCheaper: Bool
    let action: () -> Void

    var body: some View {
        let tone = isCheaper ? WidgetTone.inprog : .free
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Text(side?.string("label") ?? "—")
                .tfText(.row)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
            Spacer(minLength: TFSpacing.sm)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueText)
                    .tfText(.taskTitle)
                    .tfMonospaced(20, weight: .semibold)
                    .foregroundStyle(Color.tfText)
                if let unit {
                    Text(unit).tfText(.caption).foregroundStyle(Color.tfSub)
                }
            }
        }
        .frame(minHeight: TFHitTarget.min)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(tone: tone))
    }

    private var valueText: String {
        guard let side else { return "—" }
        if let number = side.number("value") { return WidgetFormat.integer(number) }
        return side.string("value") ?? "—"
    }

    private func accessibilityText(tone: WidgetTone) -> String {
        let label = side?.string("label") ?? "—"
        let suffix = isCheaper ? ", выгоднее" : ""
        return "\(label): \(valueText)\(suffix)"
    }
}

/// Полоса разницы: ширина половины пропорциональна значению, заливка — тоном
/// более выгодной стороны. Числа на полосе не пишем: на заливке своего цвета
/// текст не проходит контраст ни в одной теме (§1.7).
private struct CompareDifferenceBar: View {
    let left: Double
    let right: Double
    let ink: WidgetInk

    var body: some View {
        GeometryReader { geo in
            let total = max(left + right, 0.001)
            let leftShare = WidgetFormat.clamped(left / total, 0, 1)
            HStack(spacing: 2) {
                Capsule()
                    .fill(left <= right ? ink.fill(.inprog) : ink.track)
                    .frame(width: max(2, (geo.size.width - 2) * leftShare))
                Capsule().fill(ink.track)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}