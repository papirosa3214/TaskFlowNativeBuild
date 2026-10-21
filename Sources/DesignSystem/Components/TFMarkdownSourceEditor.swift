import SwiftUI

struct TFMarkdownSourceEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityLabel("Исходный Markdown заметки")
            .accessibilityIdentifier("note.markdown-source")
    }
}
