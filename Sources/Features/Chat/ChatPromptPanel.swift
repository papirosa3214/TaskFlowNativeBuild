import SwiftUI

/// Утверждённая панель чата. Управление голосом и действиями остаётся у вызывающего экрана.
struct ChatPromptPanel<Controls: View>: View {
    @Binding var text: String
    let placeholder: String
    let hidesText: Bool
    let focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(hidesText ? "" : placeholder, text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
                .focused(focus)
                .onSubmit { if !hidesText { onSubmit() } }
                .foregroundStyle(hidesText ? Color.clear : Color.tfPaper)
                .accessibilityIdentifier("chat.message")
                .padding(.horizontal, 10).padding(.top, 10)
            controls()
        }
        .padding(8)
        .background(Color(white: 0.125), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.12)))
    }
}
