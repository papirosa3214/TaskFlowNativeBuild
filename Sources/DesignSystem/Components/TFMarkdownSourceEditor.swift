import SwiftUI
import UIKit
import Observation

/// Редактор исходника: панель меняет только текст, Markdown разбирает сервер.
struct TFMarkdownSourceEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textColor = .label
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.keyboardDismissMode = .interactive
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityLabel = "Исходный Markdown заметки"
        view.accessibilityIdentifier = "note.markdown-source"
        view.delegate = context.coordinator
        view.text = text
        context.coordinator.textView = view
        view.inputAccessoryView = AccessoryContainer(host: context.coordinator)
        updateFont(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        updateFont(view)
        guard view.markedTextRange == nil, view.text != text else { return }
        let selection = view.selectedRange
        view.text = text
        let location = min(selection.location, (text as NSString).length)
        view.selectedRange = NSRange(location: location, length: min(selection.length, (text as NSString).length - location))
    }

    private func updateFont(_ view: UITextView) {
        let preferred = UIFont.preferredFont(forTextStyle: .body)
        let descriptor = preferred.fontDescriptor.withDesign(.monospaced) ?? preferred.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: 0)
        if view.font != font { view.font = font }
    }

    /// Аксессуар удерживает hosting controller; coordinator держит UITextView слабо.
    private final class AccessoryContainer: UIView {
        private let accessory: MarkdownKeyboardAccessoryHost

        init(host: MarkdownKeyboardHost) {
            accessory = MarkdownKeyboardAccessoryHost(host: host)
            super.init(frame: accessory.view.frame)
            backgroundColor = .clear
            autoresizingMask = [.flexibleWidth]
            addSubview(accessory.view)
            accessory.view.frame = bounds
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    @Observable @MainActor
    final class SelectionState { var revision = 0 }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, MarkdownKeyboardHost {
        var parent: TFMarkdownSourceEditor
        weak var textView: UITextView?
        var isUpdating = false
        private let selectionState = SelectionState()
        var activeMarks: Set<InlineMark> {
            let _ = selectionState.revision
            guard let view = textView else { return [] }
            let pairs: [(InlineMark, String, String)] = [
                (.bold, "**", "**"), (.italic, "*", "*"), (.underline, "<u>", "</u>"),
                (.strike, "~~", "~~"), (.highlight, "==", "=="), (.code, "`", "`")
            ]
            return Set(pairs.compactMap { mark, open, close in
                MarkdownSourceCommands.isWrapped(view.text, range: view.selectedRange, open: open, close: close) ? mark : nil
            })
        }
        var currentBlockKind: BlockKind? {
            let _ = selectionState.revision
            guard let view = textView else { return nil }
            let source = view.text as NSString
            let line = source.substring(with: source.lineRange(for: view.selectedRange))
            for level in (1...3).reversed() where line.hasPrefix(String(repeating: "#", count: level) + " ") {
                return .heading(level: level)
            }
            if line.hasPrefix("- [ ] ") { return .taskItem(checked: false) }
            if line.hasPrefix("- [x] ") { return .taskItem(checked: true) }
            if line.hasPrefix("- ") { return .bulletItem }
            if line.hasPrefix("1. ") { return .orderedItem }
            if line.hasPrefix("> ") { return .blockquote }
            return .paragraph
        }
        var supportsDictation: Bool { true }
        var isRecordingDictation: Bool {
            if case .recording = DictationEngine.shared.recordingState { return true }
            return false
        }
        var dictationLevel: Double { DictationEngine.shared.currentLevel }

        init(parent: TFMarkdownSourceEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            parent.text = textView.text
            selectionState.revision += 1
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if !isUpdating { selectionState.revision += 1 }
        }

        func toggleMark(_ mark: InlineMark) {
            guard let view = textView else { return }
            let delimiters: (String, String)
            switch mark {
            case .bold: delimiters = ("**", "**")
            case .italic: delimiters = ("*", "*")
            case .underline: delimiters = ("<u>", "</u>")
            case .strike: delimiters = ("~~", "~~")
            case .highlight: delimiters = ("==", "==")
            case .code: delimiters = ("`", "`")
            case .link:
                apply(MarkdownSourceCommands.link(view.text, range: view.selectedRange))
                return
            }
            apply(MarkdownSourceCommands.wrap(view.text, range: view.selectedRange, open: delimiters.0, close: delimiters.1))
        }

        func setBlockKind(_ kind: BlockKind) {
            guard let view = textView else { return }
            let marker: String
            switch kind {
            case .heading(let level): marker = String(repeating: "#", count: min(3, max(1, level))) + " "
            case .bulletItem: marker = "- "
            case .orderedItem: marker = "1. "
            case .taskItem: marker = "- [ ] "
            case .blockquote: marker = "> "
            case .codeBlock:
                apply(MarkdownSourceCommands.codeBlock(view.text, range: view.selectedRange))
                return
            default: return
            }
            apply(MarkdownSourceCommands.prefix(view.text, range: view.selectedRange, marker: marker))
        }

        func insertHorizontalRule() {
            guard let view = textView else { return }
            let source = view.text as NSString
            let end = NSMaxRange(source.lineRange(for: view.selectedRange))
            let separator = end > 0 && source.substring(with: NSRange(location: end - 1, length: 1)) != "\n" ? "\n\n---\n" : "\n---\n"
            let updated = source.replacingCharacters(in: NSRange(location: end, length: 0), with: separator)
            apply(.init(text: updated, selection: NSRange(location: end + (separator as NSString).length, length: 0)))
        }

        func dismissKeyboard() { textView?.resignFirstResponder() }

        func toggleDictation() async {
            switch DictationEngine.shared.recordingState {
            case .idle, .failed: await DictationEngine.shared.startRecording()
            case .recording:
                guard let transcript = await DictationEngine.shared.stopRecordingAndTranscribe(), let view = textView else { return }
                let source = view.text as NSString
                let range = view.selectedRange
                apply(.init(text: source.replacingCharacters(in: range, with: transcript),
                            selection: NSRange(location: range.location + (transcript as NSString).length, length: 0)))
            case .transcribing: break
            }
        }

        private func apply(_ edit: MarkdownSourceCommands.Edit) {
            guard let view = textView else { return }
            let previous = MarkdownSourceCommands.Edit(text: view.text, selection: view.selectedRange)
            view.undoManager?.registerUndo(withTarget: self) { coordinator in coordinator.apply(previous) }
            view.unmarkText()
            view.text = edit.text
            view.selectedRange = edit.selection
            parent.text = edit.text
            selectionState.revision += 1
            view.becomeFirstResponder()
            view.scrollRangeToVisible(edit.selection)
        }
    }
}

/// Команды над UTF-16-выделением; не строят документ и не интерпретируют его.
enum MarkdownSourceCommands {
    struct Edit { var text: String; var selection: NSRange }

    static func isWrapped(_ text: String, range: NSRange, open: String, close: String) -> Bool {
        let source = text as NSString
        let opening = (open as NSString).length
        let closing = (close as NSString).length
        // Одинарная * внутри ** — часть жирного, а не включённый курсив.
        var canRemove = true
        if open == "*", close == "*" {
            var count = 0
            var cursor = range.location
            while cursor > 0, source.substring(with: NSRange(location: cursor - 1, length: 1)) == "*" {
                count += 1
                cursor -= 1
            }
            canRemove = count % 2 == 1
        }
        return canRemove && range.location >= opening && NSMaxRange(range) + closing <= source.length &&
            source.substring(with: NSRange(location: range.location - opening, length: opening)) == open &&
            source.substring(with: NSRange(location: NSMaxRange(range), length: closing)) == close
    }

    static func wrap(_ text: String, range: NSRange, open: String, close: String) -> Edit {
        let source = text as NSString
        let opening = (open as NSString).length
        let closing = (close as NSString).length
        if isWrapped(text, range: range, open: open, close: close) {
            let whole = NSRange(location: range.location - opening, length: opening + range.length + closing)
            return Edit(text: source.replacingCharacters(in: whole, with: source.substring(with: range)),
                        selection: NSRange(location: whole.location, length: range.length))
        }
        return Edit(text: source.replacingCharacters(in: range, with: open + source.substring(with: range) + close),
                    selection: NSRange(location: range.location + opening, length: range.length))
    }

    static func link(_ text: String, range: NSRange) -> Edit {
        let source: String
        let label: NSRange
        if range.length == 0 {
            source = (text as NSString).replacingCharacters(in: range, with: "Ссылка")
            label = NSRange(location: range.location, length: ("Ссылка" as NSString).length)
        } else { source = text; label = range }
        var edit = wrap(source, range: label, open: "[", close: "](https://)")
        if (edit.text as NSString).length > (source as NSString).length {
            edit.selection = NSRange(location: edit.selection.location + edit.selection.length + 2, length: 8)
        }
        return edit
    }

    static func prefix(_ text: String, range: NSRange, marker: String) -> Edit {
        let source = text as NSString
        let whole = source.lineRange(for: range)
        let original = source.substring(with: whole)
        let trailingNewline = original.hasSuffix("\n")
        let body = trailingNewline ? String(original.dropLast()) : original
        let lines = body.components(separatedBy: "\n")
        let remove = lines.allSatisfy { $0.hasPrefix(marker) }
        let changed = lines.map { line -> String in
            if remove { return String(line.dropFirst(marker.count)) }
            if marker.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }
                if !hashes.isEmpty, line.dropFirst(hashes.count).hasPrefix(" ") {
                    return marker + line.dropFirst(hashes.count + 1)
                }
            }
            return marker + line
        }
        let replacement = changed.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let selection: NSRange
        if range.length == 0 {
            let delta = (changed[0] as NSString).length - (lines[0] as NSString).length
            selection = NSRange(location: max(whole.location, range.location + delta), length: 0)
        } else {
            selection = NSRange(location: whole.location, length: (replacement as NSString).length)
        }
        return Edit(text: source.replacingCharacters(in: whole, with: replacement), selection: selection)
    }

    static func codeBlock(_ text: String, range: NSRange) -> Edit {
        let source = text as NSString
        var whole = source.lineRange(for: range)
        if whole.length > 0, source.substring(with: NSRange(location: NSMaxRange(whole) - 1, length: 1)) == "\n" {
            whole.length -= 1
        }
        return wrap(text, range: whole, open: "```\n", close: "\n```")
    }
}
