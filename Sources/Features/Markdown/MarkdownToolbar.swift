import SwiftUI
import UIKit

// ═══════════ Тулбар пометок над клавиатурой ═══════════
//
// `inputAccessoryView` для UITextView в MarkdownEditorView. Кнопки двух
// типов:
//
//   • Inline-марки (B, I, S, code, link): меняют атрибуты выделения
//     в фокусированном блоке. Действие идёт через `MarkdownToolbarHost`
//     и `FocusedBlockController` — тулбар НЕ лезет в UITextView
//     напрямую, а вызывает колбэк, который обновит state.
//
//   • Блочные переключатели (H1, H2, H3, list, checklist, quote, code):
//     меняют kind блока — родительский `MarkdownEditorView` обрабатывает
//     это, заменяя `BlockKind` и перерендеривая.
//
// Тулбар НЕ стеклянный — обычный UIToolbar с системными кнопками.
// См. память агента (раздел 6/7): `.glassEffect` / `.background(material)`
// на inputAccessoryView ломает hit-testing кнопок на iOS 26.5.

struct MarkdownToolbar: View {
    /// Колбэк на действие с инлайн-маркой. Параметр — `InlineMark` из
    /// `MarkdownText.swift`. Семантика: переключить марк на выделении
    /// (или вставить маркеры вокруг, если выделения нет).
    let onToggleMark: (InlineMark) -> Void
    /// Колбэк на действие с блоком — параметр `BlockKind` означает
    /// «привести текущий блок к этому типу» (или «вставить блок»,
    /// если фокус на пустом документе).
    let onSetBlockKind: (BlockKind) -> Void

    /// Текущий набор активных марок на выделении — чтобы подсветить
    /// нажатые кнопки. Если nil — ни одна кнопка не подсвечена.
    var activeMarks: Set<InlineMark> = []
    var currentBlockKind: BlockKind? = nil

    var body: some View {
        HStack(spacing: 4) {
            Group {
                markButton(.bold, systemImage: "bold", label: "Жирный")
                markButton(.italic, systemImage: "italic", label: "Курсив")
                markButton(.strike, systemImage: "strikethrough", label: "Зачёркнутый")
                markButton(.code, systemImage: "chevron.left.forwardslash.chevron.right", label: "Код")
                markButton(.link, systemImage: "link", label: "Ссылка")
            }
            Divider().frame(height: 22).padding(.horizontal, 2)
            Group {
                blockButton(.heading(level: 1), systemImage: "h.square", label: "H1")
                blockButton(.heading(level: 2), systemImage: "h.square.fill", label: "H2")
                blockButton(.heading(level: 3), systemImage: "h.circle", label: "H3")
                blockButton(.bulletItem, systemImage: "list.bullet", label: "Список")
                blockButton(.taskItem(checked: false), systemImage: "checklist", label: "Чек-лист")
                blockButton(.blockquote, systemImage: "text.quote", label: "Цитата")
                blockButton(.codeBlock(language: nil), systemImage: "curlybraces", label: "Код-блок")
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func markButton(_ mark: InlineMark, systemImage: String, label: String) -> some View {
        Button {
            onToggleMark(mark)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .background(
                    activeMarks.contains(mark)
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func blockButton(_ kind: BlockKind, systemImage: String, label: String) -> some View {
        Button {
            onSetBlockKind(kind)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .background(
                    currentBlockKind.map { isSameKind($0, kind) } ?? false
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Сравнение `BlockKind` по смыслу (для подсветки активной кнопки
    /// в тулбаре). У `taskItem` не важен чек — кнопка одна, чек
    /// переключается отдельно.
    private func isSameKind(_ a: BlockKind, _ b: BlockKind) -> Bool {
        switch (a, b) {
        case (.paragraph, .paragraph): return true
        case (.heading(let x), .heading(let y)): return x == y
        case (.bulletItem, .bulletItem): return true
        case (.orderedItem, .orderedItem): return true
        case (.taskItem, .taskItem): return true
        case (.blockquote, .blockquote): return true
        case (.codeBlock, .codeBlock): return true
        case (.horizontalRule, .horizontalRule): return true
        default: return false
        }
    }
}

// MARK: - Мост к UITextView (inputAccessoryView)

/// SwiftUI-обёртка для установки MarkdownToolbar как `inputAccessoryView`
/// заданного UITextView. Использовать из родительского контроллера:
///
///     textView.inputAccessoryView = UIHostingController(
///         rootView: MarkdownToolbarAccessory(
///             toolbar: MarkdownToolbar(...),
///             host: self
///         )
///     ).view
///
/// Хост — любой объект, реализующий `MarkdownToolbarHost`.
final class MarkdownToolbarAccessory: UIView {
    private let hosting: UIHostingController<MarkdownToolbar>?

    init(toolbar: MarkdownToolbar) {
        let host = UIHostingController(rootView: toolbar)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        self.hosting = host
        super.init(frame: .zero)
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }
}

/// Контракт между тулбаром и редактором: вызывающий передаёт фокус
/// и текущее выделение, тулбар дёргает методы `toggleMark` / `setBlockKind`.
@MainActor
protocol MarkdownToolbarHost: AnyObject {
    /// Переключить марку на текущем выделении в фокусированном блоке
    /// (или вставить маркеры вокруг, если выделения нет).
    func toggleMark(_ mark: InlineMark)
    /// Привести текущий блок к указанному типу.
    func setBlockKind(_ kind: BlockKind)
    /// Текущие активные марки на выделении (для подсветки кнопок).
    var activeMarks: Set<InlineMark> { get }
    /// Текущий тип фокусированного блока (для подсветки кнопок).
    var currentBlockKind: BlockKind? { get }
}
