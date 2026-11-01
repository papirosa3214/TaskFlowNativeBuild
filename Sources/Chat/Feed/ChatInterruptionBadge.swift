import SwiftUI

/// Значок прерванного ответа роли под ответом в ленте (карточка b504958a).
/// Ответ, остановленный уточнением владельца, не должен выглядеть как
/// завершённый: сервер сам помечает, что он сохранён частично.
struct ChatInterruptionBadge: View {
    let interruption: ChatMessageInterruption
    let isPartial: Bool

    var body: some View {
        TFPill(surface: .clear, radius: 0) {
            HStack(spacing: TFSpacing.xs) {
                Image(systemName: "arrow.triangle.branch")
                    .tfText(.meta)
                    .accessibilityHidden(true)
                Text(label).tfText(.meta)
            }
            .foregroundStyle(Color.tfOrange)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ответ прерван: \(label)")
        .accessibilityIdentifier("chat.interrupted")
    }

    private var label: String {
        isPartial ? "\(interruption.label), сохранён частично" : interruption.label
    }
}