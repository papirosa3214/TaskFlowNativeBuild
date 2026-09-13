import SwiftUI
import UIKit

// ═══════════ Markdown-редактор (WYSIWYG + источник) ═══════════
//
// SwiftUI-обёртка над UITextView: один экземпляр на блок, блоки
// складываются в VStack. Хранит истину как `blocks: [NoteBlock]`.
//
// Тулбар: один экземпляр на весь редактор (через `MarkdownEditorCoordinator`),
// ставится `inputAccessoryView` каждому UITextView.
//
// Чего НЕ делает:
//   • таблиц, drag-and-drop картинок, спец-логики ячеек таблицы.
//   • скрытия markdown-разметочных символов (как Obsidian live preview).

struct MarkdownEditorView: View {
    @Binding var blocks: [NoteBlock]
    @Binding var mode: MarkdownEditorMode
    var collapsesToSingleBlock: Bool = false

    @StateObject private var coordinator = MarkdownEditorCoordinator()
    @State private var focusedBlockID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                MarkdownBlockEditor(
                    block: block,
                    mode: mode,
                    isFocused: focusedBlockID == block.id,
                    coordinator: coordinator,
                    onFocus: {
                        focusedBlockID = block.id
                        coordinator.focusedBlockID = block.id
                    },
                    onChange: { newRuns in
                        if let idx = blocks.firstIndex(where: { $0.id == block.id }) {
                            blocks[idx].runs = newRuns
                        }
                    }
                )
                .frame(minHeight: minHeight(for: block.kind))
            }

            if !collapsesToSingleBlock {
                Button {
                    addBlock()
                } label: {
                    Label("Добавить блок", systemImage: "plus.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .onAppear {
            coordinator.onSetBlockKind = { [blocks] kind in
                guard let focusedID = coordinator.focusedBlockID,
                      let idx = blocks.firstIndex(where: { $0.id == focusedID }) else { return }
                var newBlocks = blocks
                newBlocks[idx].kind = kind
                self.blocks = newBlocks
            }
            coordinator.onRunsChange = { [blocks] blockID, runs in
                guard let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                var newBlocks = blocks
                newBlocks[idx].runs = runs
                self.blocks = newBlocks
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

    private func addBlock() {
        let new = NoteBlock(kind: .paragraph)
        if let focusedID = coordinator.focusedBlockID,
           let idx = blocks.firstIndex(where: { $0.id == focusedID }) {
            blocks.insert(new, at: idx + 1)
        } else {
            blocks.append(new)
        }
        coordinator.focusedBlockID = new.id
    }
}

/// Режим отображения редактора.
enum MarkdownEditorMode: String, CaseIterable {
    case rendered  // WYSIWYG-вид: атрибутированный текст
    case source    // Сырой markdown
}

// MARK: - Координатор (тулбар, фокус, активные марки)

@MainActor
final class MarkdownEditorCoordinator: ObservableObject, MarkdownToolbarHost {
    lazy var toolbarAccessory: UIView = MarkdownToolbarAccessory(
        toolbar: MarkdownToolbar(
            onToggleMark: { [weak self] mark in self?.toggleMark(mark) },
            onSetBlockKind: { [weak self] kind in self?.setBlockKind(kind) }
        )
    )

    var focusedBlockID: UUID?
    weak var focusedTextView: UITextView?
    var onSetBlockKind: ((BlockKind) -> Void)?
    var onRunsChange: ((UUID, [RichRun]) -> Void)?

    func toggleMark(_ mark: InlineMark) {
        guard let tv = focusedTextView else { return }
        let range = tv.selectedRange
        guard range.length > 0 else { return }
        let attr = MarkdownMarkKey.attributeKey(for: mark)
        let storage = tv.textStorage
        storage.beginEditing()
        switch mark {
        case .link:
            storage.addAttribute(attr, value: "https://", range: range)
            storage.addAttribute(.foregroundColor, value: UIColor(Color.tfRed), range: range)
        case .code:
            let base = MarkdownText.baseFont(for: .paragraph)
            let attrs = MarkdownText.attributes(for: RichRun(text: "", code: true), base: base)
            for (key, value) in attrs { storage.addAttribute(key, value: value, range: range) }
        default:
            let existing = storage.attribute(attr, at: range.location, effectiveRange: nil) as? Bool
            if existing == true {
                storage.removeAttribute(attr, range: range)
            } else {
                storage.addAttribute(attr, value: true, range: range)
            }
            applyVisualAttribute(for: mark, in: storage, range: range, on: existing != true)
        }
        storage.endEditing()
        let runs = MarkdownText.runs(from: tv.attributedText)
        if let id = focusedBlockID {
            onRunsChange?(id, runs)
        }
    }

    func setBlockKind(_ kind: BlockKind) {
        guard focusedBlockID != nil else { return }
        onSetBlockKind?(kind)
    }

    var activeMarks: Set<InlineMark> {
        guard let tv = focusedTextView, tv.selectedRange.length > 0 else { return [] }
        let range = tv.selectedRange
        let storage = tv.textStorage
        var marks: Set<InlineMark> = []
        if (storage.attribute(MarkdownMarkKey.bold, at: range.location, effectiveRange: nil) as? Bool) == true {
            marks.insert(.bold)
        }
        if (storage.attribute(MarkdownMarkKey.italic, at: range.location, effectiveRange: nil) as? Bool) == true {
            marks.insert(.italic)
        }
        if (storage.attribute(MarkdownMarkKey.underline, at: range.location, effectiveRange: nil) as? Bool) == true {
            marks.insert(.underline)
        }
        if (storage.attribute(MarkdownMarkKey.strike, at: range.location, effectiveRange: nil) as? Bool) == true {
            marks.insert(.strike)
        }
        if (storage.attribute(MarkdownMarkKey.code, at: range.location, effectiveRange: nil) as? Bool) == true {
            marks.insert(.code)
        }
        if (storage.attribute(MarkdownMarkKey.link, at: range.location, effectiveRange: nil) as? String) != nil {
            marks.insert(.link)
        }
        return marks
    }

    var currentBlockKind: BlockKind? { nil }

    private func applyVisualAttribute(for mark: InlineMark, in storage: NSTextStorage, range: NSRange, on: Bool) {
        switch mark {
        case .bold:
            let base = MarkdownText.baseFont(for: .paragraph)
            let attrs = MarkdownText.attributes(for: RichRun(text: "", bold: on), base: base)
            for (key, value) in attrs where key == .font {
                storage.addAttribute(key, value: value, range: range)
            }
        case .italic:
            let base = MarkdownText.baseFont(for: .paragraph)
            let attrs = MarkdownText.attributes(for: RichRun(text: "", italic: on), base: base)
            for (key, value) in attrs where key == .font {
                storage.addAttribute(key, value: value, range: range)
            }
        case .underline:
            if on {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                storage.removeAttribute(.underlineStyle, range: range)
            }
        case .strike:
            if on {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                storage.removeAttribute(.strikethroughStyle, range: range)
            }
        default:
            break
        }
    }
}

extension MarkdownMarkKey {
    static func attributeKey(for mark: InlineMark) -> NSAttributedString.Key {
        switch mark {
        case .bold: MarkdownMarkKey.bold
        case .italic: MarkdownMarkKey.italic
        case .underline: MarkdownMarkKey.underline
        case .strike: MarkdownMarkKey.strike
        case .highlight: MarkdownMarkKey.highlight
        case .code: MarkdownMarkKey.code
        case .link: MarkdownMarkKey.link
        }
    }
}

// MARK: - GrowingTextView (подкласс UITextView)

/// Подкласс UITextView, который публикует `intrinsicContentSize` после
/// каждого layout-прохода. Без этого UITextView в SwiftUI List не растёт
/// по высоте — текст уходит за края экрана. Тот же приём, что в
/// `NoteBlockTextView.swift` (NoteUITextView).
final class GrowingTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let fitting = sizeThatFits(CGSize(
            width: max(bounds.width, 1),
            height: .greatestFiniteMagnitude
        ))
        return CGSize(
            width: UIView.noIntrinsicMetric,
            height: max(fitting.height, 22)
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Редактор одного блока

private struct MarkdownBlockEditor: View {
    let block: NoteBlock
    let mode: MarkdownEditorMode
    let isFocused: Bool
    @ObservedObject var coordinator: MarkdownEditorCoordinator
    let onFocus: () -> Void
    let onChange: ([RichRun]) -> Void

    var body: some View {
        BlockTextRepresentable(
            block: block,
            mode: mode,
            coordinator: coordinator,
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

/// UIViewRepresentable, держащий UITextView для одного блока.
private struct BlockTextRepresentable: UIViewRepresentable {
    let block: NoteBlock
    let mode: MarkdownEditorMode
    let coordinator: MarkdownEditorCoordinator
    let onFocus: () -> Void
    let onChange: ([RichRun]) -> Void

    func makeUIView(context: Context) -> GrowingTextView {
        let tv = GrowingTextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.heightTracksTextView = false
        tv.adjustsFontForContentSizeCategory = true
        tv.font = MarkdownText.baseFont(for: block.kind)
        tv.inputAccessoryView = coordinator.toolbarAccessory
        tv.attributedText = makeAttributed(for: block)
        return tv
    }

    func updateUIView(_ tv: GrowingTextView, context: Context) {
        if tv.inputAccessoryView !== coordinator.toolbarAccessory {
            tv.inputAccessoryView = coordinator.toolbarAccessory
        }
        let currentAttributed = tv.attributedText
        let expected = makeAttributed(for: block)
        if currentAttributed?.string != expected.string {
            tv.attributedText = expected
        }
        tv.font = MarkdownText.baseFont(for: block.kind)
    }

    private func makeAttributed(for block: NoteBlock) -> NSAttributedString {
        switch mode {
        case .rendered:
            return MarkdownText.attributedString(runs: block.runs, blockKind: block.kind)
        case .source:
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
            parent.coordinator.focusedTextView = textView
            parent.onFocus()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.coordinator.focusedTextView === textView {
                parent.coordinator.focusedTextView = nil
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            switch parent.mode {
            case .rendered:
                let runs = MarkdownText.runs(from: textView.attributedText)
                parent.onChange(runs)
            case .source:
                let parsed = MarkdownParser.parse(textView.text)
                let runs = parsed.first?.runs ?? []
                parent.onChange(runs)
            }
        }
    }
}
