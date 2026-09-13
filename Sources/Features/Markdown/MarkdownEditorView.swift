import SwiftUI
import UIKit

// ═══════════ Markdown-редактор (WYSIWYG + источник) ═══════════
//
// SwiftUI-обёртка над UITextView: один экземпляр на блок, блоки
// складываются в VStack. Хранит истину как `blocks: [NoteBlock]`.
//
// Режимы:
//   • `.rendered` (по умолчанию) — UITextView показывает NSAttributedString,
//     текст выглядит отформатированным, тулбар меняет атрибуты выделения
//     (bold/italic/.../ссылка) на лету. Это и есть «WYSIWYG» в нашем
//     понимании: визуально форматированный текст при правке.
//   • `.source` — UITextView показывает сырой markdown (то, что уйдёт
//     на сервер / в файл). Полезно для тонкой правки разметки.
//
// Toolbar (MarkdownToolbar) — `inputAccessoryView` UITextView, нажатия
// идут в FocusedBlockController и меняют атрибуты в фокусированном блоке.
//
// Чего НЕ делает (по сравнению с NoteBlockTextView):
//   • таблиц — markdown-вариант редактора таблиц не входит в скоуп
//   • drag-and-drop картинок
//   • спец-логики ячеек таблицы
//
// Скоуп LOCK-142 — markdown-редактор для карточки задачи и заметок.
// Один блок = один UITextView: простая модель, без зон и переплетений.

struct MarkdownEditorView: View {
    @Binding var blocks: [NoteBlock]
    @Binding var mode: MarkdownEditorMode
    /// Если задан — оборачивает содержимое в один блок-параграф и редактирует
    /// как одну строку (для карточки задачи). Если nil — каждый блок
    /// редактируется отдельно (для заметок).
    var collapsesToSingleBlock: Bool = false

    @State private var focusedBlockID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                MarkdownBlockEditor(
                    block: block,
                    mode: mode,
                    isFocused: focusedBlockID == block.id,
                    onFocus: { focusedBlockID = block.id },
                    onChange: { newRuns in
                        if let idx = blocks.firstIndex(where: { $0.id == block.id }) {
                            blocks[idx].runs = newRuns
                        }
                    },
                    onDelete: {
                        if blocks.count > 1 {
                            blocks.removeAll { $0.id == block.id }
                        }
                    }
                )
                .frame(minHeight: minHeight(for: block.kind))
            }

            if !collapsesToSingleBlock {
                Button {
                    addBlock(after: blocks.last)
                } label: {
                    Label("Добавить блок", systemImage: "plus.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func minHeight(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading: 36
        case .codeBlock: 80
        default: 28
        }
    }

    private func addBlock(after block: NoteBlock?) {
        let new = NoteBlock(kind: .paragraph)
        if let block, let idx = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks.insert(new, at: idx + 1)
        } else {
            blocks.append(new)
        }
    }
}

/// Режим отображения редактора.
enum MarkdownEditorMode: String, CaseIterable {
    case rendered  // WYSIWYG-вид: атрибутированный текст
    case source    // Сырой markdown
}

// MARK: - Редактор одного блока

private struct MarkdownBlockEditor: View {
    let block: NoteBlock
    let mode: MarkdownEditorMode
    let isFocused: Bool
    let onFocus: () -> Void
    let onChange: ([RichRun]) -> Void
    let onDelete: () -> Void

    var body: some View {
        BlockTextRepresentable(
            block: block,
            mode: mode,
            onFocus: onFocus,
            onChange: onChange
        )
        .frame(minHeight: 0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}

/// UIViewRepresentable, держащий UITextView для одного блока. Связь
/// с родителем — через `onChange(runs:)` для rendered и через прямые
/// `onChange(text:)` для source.
private struct BlockTextRepresentable: UIViewRepresentable {
    let block: NoteBlock
    let mode: MarkdownEditorMode
    let onFocus: () -> Void
    let onChange: ([RichRun]) -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.font = MarkdownText.baseFont(for: block.kind)
        applyContent(to: tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // При обновлении блока снаружи (например, загрузка из markdown)
        // нужно переустановить attributedText — но только если содержимое
        // реально изменилось, чтобы не сбрасывать курсор при наборе.
        let currentAttributed = tv.attributedText
        let expected = makeAttributed(for: block)
        if currentAttributed?.string != expected.string
            || currentAttributed?.attributes(at: 0, effectiveRange: nil) != expected.attributes(at: 0, effectiveRange: nil) {
            // Простое сравнение — по строке. Для полноценного diff'а
            // атрибутов нужна отдельная логика; пока достаточно того, что
            // пользователь печатает в source-режиме и его правки не
            // затираются (нет внешнего апдейта, пока он печатает).
            tv.attributedText = expected
        }
        tv.font = MarkdownText.baseFont(for: block.kind)
    }

    private func applyContent(to tv: UITextView) {
        tv.attributedText = makeAttributed(for: block)
    }

    private func makeAttributed(for block: NoteBlock) -> NSAttributedString {
        switch mode {
        case .rendered:
            return MarkdownText.attributedString(runs: block.runs, blockKind: block.kind)
        case .source:
            // Для source-режима просто текст прогона (markdown-разметка
            // присутствует как есть) — кодировщик энкодит блок целиком,
            // но для одного блока нам нужен только инлайн.
            let md = MarkdownEncoder.encode([block])
            return NSAttributedString(
                string: md,
                attributes: [
                    .font: MarkdownText.baseFont(for: block.kind),
                    .foregroundColor: UIColor.label
                ]
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextRepresentable
        init(parent: BlockTextRepresentable) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus()
        }

        func textViewDidChange(_ textView: UITextView) {
            switch parent.mode {
            case .rendered:
                let runs = MarkdownText.runs(from: textView.attributedText)
                parent.onChange(runs)
            case .source:
                let parsed = MarkdownParser.parse(textView.text)
                // Берём runs первого блока — в source-режиме один блок =
                // один редактор; многострочный исходник разбирается на
                // несколько блоков при сохранении, а не в реальном времени.
                let runs = parsed.first?.runs ?? []
                parent.onChange(runs)
            }
        }
    }
}
