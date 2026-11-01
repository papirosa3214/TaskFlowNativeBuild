import SwiftUI

/// Знак вопроса рядом с подписью: пояснение открывается по нажатию, а не
/// занимает место в форме постоянным текстом (владелец 30.10.2026: «не
/// подписи делай, а вопросительные значки, на которые кликнуть»).
public struct TFInfoHint: View {
    private let text: String
    @State private var isPresented = false

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .tfTypeFont(size: 15, weight: .regular)
                .foregroundStyle(Color.tfDim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            Text(text)
                .tfText(.caption)
                .foregroundStyle(Color.tfText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(TFSpacing.md)
                .frame(maxWidth: 300)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Пояснение")
        .accessibilityHint(text)
    }
}
