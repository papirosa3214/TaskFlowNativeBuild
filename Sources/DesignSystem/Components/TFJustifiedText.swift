import SwiftUI
import UIKit

// Текст, выровненный по ширине (оба края ровные, не «рваный» правый край) —
// просьба владельца 03.09.2026: «текст выравнивание по ширине, задрала эта
// вёрстка кривущая, всё влево уходящее». Проверено: SwiftUI `Text`/
// `.multilineTextAlignment(_:)` умеет только leading/center/trailing —
// настоящего justify там нет (`TextAlignment` — не `NSTextAlignment`, кейса
// `.justified` в SwiftUI не существует). Мост на `UILabel` — тот честно
// умеет `NSTextAlignment.justified` через TextKit.
//
// Шрифт/трекинг дублируют числа `TFFont`/`TFTextStyle` (Typography.swift) —
// `Font` из SwiftUI не отдаёт обратно размер/начертание, чтобы собрать
// `UIFont` программно, поэтому таблица здесь своя, но те же цифры.
public struct TFJustifiedText: UIViewRepresentable {
    let text: String
    let style: TFTextStyle
    let color: UIColor

    public init(_ text: String, style: TFTextStyle = .action, color: Color = .primary) {
        self.text = text
        self.style = style
        self.color = UIColor(color)
    }

    public func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    public func updateUIView(_ label: UILabel, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: style.uiFont,
            .foregroundColor: color,
            .kern: style.uiKerning,
            .paragraphStyle: paragraph,
        ])
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingCompressedSize.width
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

extension TFTextStyle {
    /// Та же ступень шкалы, что и `font`/`tracking` (Typography.swift), но
    /// как `UIFont`/пункты кёрнинга — то, что просит `NSAttributedString`.
    fileprivate var uiFont: UIFont {
        switch self {
        case .titleLarge: .systemFont(ofSize: 28, weight: .bold)
        case .taskTitle: .systemFont(ofSize: 20, weight: .semibold)
        case .title: .systemFont(ofSize: 17, weight: .semibold)
        case .input: .systemFont(ofSize: 16, weight: .regular)
        case .body: .systemFont(ofSize: 15, weight: .regular)
        case .row: .systemFont(ofSize: 14, weight: .regular)
        case .action: .systemFont(ofSize: 13, weight: .regular)
        case .meta: .systemFont(ofSize: 12, weight: .medium)
        case .caption: .systemFont(ofSize: 11, weight: .medium)
        case .micro: .systemFont(ofSize: 10, weight: .medium)
        }
    }

    fileprivate var uiKerning: CGFloat {
        switch self {
        case .titleLarge: TFFont.titleLargeTracking
        case .taskTitle: TFFont.taskTitleTracking
        case .title: TFFont.titleTracking
        case .input: TFFont.inputTracking
        case .body: TFFont.bodyTracking
        case .row: 0
        case .action: TFFont.actionTracking
        case .meta: TFFont.metaTracking
        case .caption: TFFont.captionTracking
        case .micro: TFFont.microTracking
        }
    }
}
