import SwiftUI
import UIKit

/// «Выделить текст» (владелец 20.10.2026): системное выделение с двумя
/// ручками, лупой и «Скопировать», как в ChatGPT. В ленте текст рисует
/// SwiftUI — там iOS даёт только «скопировать всё», поэтому сообщение
/// открывается здесь, в системном текстовом поле.
struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .padding(.horizontal, TFSpacing.lg)
                .tfScreenBackground()
                .navigationTitle("Выделить текст")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Мост к UITextView: только чтение, выделение включено, шрифт масштабируется
/// с системным размером текста (15 pt — токен `.body`).
private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 15))
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 24, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = [.link]
        view.accessibilityIdentifier = "chat.selectable-text"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}
