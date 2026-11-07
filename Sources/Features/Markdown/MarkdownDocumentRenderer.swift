import SwiftUI

/// Блоки чтения документа. Модель данных сохраняет разметку, а визуальный
/// стиль целиком остаётся приложению.
enum DocumentContentBlock: Equatable {
    case paragraph([RichRun])
    case heading(level: Int, runs: [RichRun])
    case listItem(kind: DocumentListItemKind, depth: Int, runs: [RichRun])
    case quote([RichRun])
    case code(text: String, language: String?)
    case table([NoteTableRow])
    case horizontalRule
}

enum DocumentListItemKind: Equatable {
    case bullet
    case ordered
    case task(checked: Bool)
}

enum MarkdownDocumentAdapter {
    static func blocks(from markdown: String) -> [DocumentContentBlock] {
        MarkdownParser.parse(markdown).map { block in
            switch block.kind {
            case .paragraph:
                .paragraph(block.runs)
            case .heading(let level):
                .heading(level: level, runs: block.runs)
            case .bulletItem:
                .listItem(kind: .bullet, depth: block.level, runs: block.runs)
            case .orderedItem:
                .listItem(kind: .ordered, depth: block.level, runs: block.runs)
            case .taskItem(let checked):
                .listItem(kind: .task(checked: checked), depth: block.level, runs: block.runs)
            case .blockquote:
                .quote(block.runs)
            case .codeBlock(let language):
                .code(text: block.runs.map(\.text).joined(), language: language)
            case .table(let rows):
                .table(rows)
            case .horizontalRule:
                .horizontalRule
            }
        }
    }
}

struct MarkdownDocumentRenderer: View {
    let markdown: String

    var body: some View {
        StructuredDocumentBlocksView(blocks: MarkdownDocumentAdapter.blocks(from: markdown))
    }
}

/// Общая презентация Markdown и простых JSON-блоков: одна иерархия,
/// типографика, переносы и оформление таблиц.
struct StructuredDocumentBlocksView: View {
    let blocks: [DocumentContentBlock]

    private var orderedNumbers: [Int: Int] {
        var counters: [Int: Int] = [:]
        var numbers: [Int: Int] = [:]
        for (index, block) in blocks.enumerated() {
            if case .listItem(kind: .ordered, depth: let depth, runs: _) = block {
                let next = (counters[depth] ?? 0) + 1
                counters[depth] = next
                counters = counters.filter { $0.key <= depth }
                numbers[index] = next
            } else if case .listItem = block {
                continue
            } else {
                counters = [:]
            }
        }
        return numbers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                StructuredDocumentBlockView(block: block, orderedNumber: orderedNumbers[index] ?? 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Color.tfRed)
    }
}

struct StructuredDocumentBlockView: View {
    @Environment(\.tfTypeSettingsEnabled) private var typeSettingsEnabled
    @AppStorage(TFTypeScale.revisionKey) private var typeRevision = 0
    let block: DocumentContentBlock
    var orderedNumber = 1

    var body: some View {
        let _ = typeRevision
        switch block {
        case .paragraph(let runs):
            inline(runs, style: .body)
        case .heading(let level, let runs):
            inline(runs, style: level == 1 ? .taskTitle : .title)
                .padding(.top, TFSpacing.xs)
        case .listItem(let kind, let depth, let runs):
            listRow(kind: kind, depth: depth, runs: runs)
        case .quote(let runs):
            HStack(alignment: .top, spacing: TFSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.tfStroke)
                    .frame(width: 3)
                inline(runs, style: .body)
                    .foregroundStyle(Color.tfSub)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text, let language):
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(typeSettingsEnabled ? .system(.callout, design: .monospaced) : .tfChat(.mono))
                        .foregroundStyle(Color.tfText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(TFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.md))
        case .table(let rows):
            DocumentTableView(rows: rows)
        case .horizontalRule:
            Divider()
        }
    }

    private func inline(_ runs: [RichRun], style: TFTextStyle) -> some View {
        runs.reduce(Text("")) { result, run in
            let piece = Text(RoleReplyMarkdown.attributed([run], chatGroup: typeSettingsEnabled ? nil : style.chatGroup))
                .fontWeight(run.bold ? .semibold : nil)
                .foregroundColor(run.bold ? Color.tfText : Color.tfText.opacity(0.9))
            return Text("\(result)\(piece)")
        }
            .tfText(style)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func listRow(kind: DocumentListItemKind, depth: Int, runs: [RichRun]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            marker(kind)
                .foregroundStyle(Color.tfSub)
                .frame(minWidth: 18, alignment: .trailing)
            inline(runs, style: .body)
        }
        .padding(.leading, CGFloat(depth) * TFSpacing.lg)
    }

    @ViewBuilder
    private func marker(_ kind: DocumentListItemKind) -> some View {
        switch kind {
        case .bullet:
            Text("•")
        case .ordered:
            Text("\(orderedNumber).")
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square" : "square")
                .font(.body)
        }
    }

}

/// Рисует исходные runs ячеек напрямую: повторно разбирать их как Markdown
/// нельзя — экранированные символы и код с `|` тогда меняют значение.
private struct DocumentTableView: View {
    @Environment(\.tfTypeSettingsEnabled) private var typeSettingsEnabled
    @AppStorage(TFTypeScale.revisionKey) private var typeRevision = 0
    let rows: [NoteTableRow]
    private static let maxCellWidth: CGFloat = 220

    private var columnWidths: [CGFloat] {
        let count = rows.map(\.cells.count).max() ?? 0
        return (0..<count).map { column in
            let widest = rows.compactMap { $0.cells.indices.contains(column) ? $0.cells[column].plainText.count : nil }.max() ?? 0
            return min(max(88, CGFloat(widest) * 10 + TFSpacing.md * 2), Self.maxCellWidth)
        }
    }

    var body: some View {
        let _ = typeRevision
        TFCard(padding: 0, surface: .card, radius: TFRadius.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    if let header = rows.first {
                        TFCard(padding: 0, surface: .card2, radius: nil) {
                            row(header, isHeader: true)
                        }
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width)
                            }
                    }
                    ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { index, item in
                        row(item, isHeader: false)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.tfCard2.opacity(0.45))
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.tfStroke.opacity(0.7)).frame(height: TFBorder.width)
                            }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: TFRadius.lg).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
        .tint(Color.tfRed)
    }

    private func row(_ item: NoteTableRow, isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(item.cells.enumerated()), id: \.offset) { column, cell in
                if column < columnWidths.count {
                    Text(RoleReplyMarkdown.attributed(cell.runs, chatGroup: typeSettingsEnabled ? nil : isHeader || cell.isHeader ? .heading : .body))
                        .tfText(.body)
                        .fontWeight(isHeader || cell.isHeader ? .semibold : nil)
                        .foregroundStyle(Color.tfText)
                        .frame(width: max(1, columnWidths[column] - TFSpacing.md * 2), alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, TFSpacing.md)
                        .padding(.vertical, TFSpacing.sm)
                        .frame(width: columnWidths[column], alignment: .leading)
                        // Вертикальные линии между столбцами — той же
                        // толщины и цвета, что горизонтальные между строками
                        // (владелец 19.10.2026). У последнего столбца линии
                        // нет: справа его закрывает рамка таблицы.
                        .frame(maxHeight: .infinity, alignment: .top)
                        .overlay(alignment: .trailing) {
                            if column < columnWidths.count - 1 {
                                Rectangle()
                                    .fill(isHeader ? Color.tfStroke : Color.tfStroke.opacity(0.7))
                                    .frame(width: TFBorder.width)
                            }
                        }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MarkdownDocumentPreviewScreen: View {
    let title: String
    private let noteID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var markdown: String?
    @State private var serverDocument: NoteDocument?
    @State private var isLoading: Bool
    @State private var errorMessage: String?

    init(noteID: String, title: String) {
        self.title = title
        self.noteID = noteID
        _markdown = State(initialValue: nil)
        _isLoading = State(initialValue: true)
    }

    init(previewMarkdown: String, title: String) {
        self.title = title
        self.noteID = nil
        _markdown = State(initialValue: previewMarkdown)
        _isLoading = State(initialValue: false)
    }

    var body: some View {
        ZStack {
            TFScreenFill()
            ScrollView {
                Group {
                    if let serverDocument {
                        RoleReplyMarkdown(text: markdown ?? "", prepared: [.document(serverDocument.blocks, chars: markdown?.count ?? 0)])
                            .textSelection(.enabled)
                    } else if let markdown {
                        Text(markdown).textSelection(.enabled)
                    } else if isLoading {
                        TFLoading(.block)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        Text(errorMessage ?? "Документ не содержит текста.")
                            .tfText(.body)
                            .foregroundStyle(Color.tfSub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.md)
            }
        }
        .tfNativeHeader(title, displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
        .task { await loadDocument() }
        .accessibilityIdentifier("markdown-document-preview")
    }

    @MainActor
    private func loadDocument() async {
        guard let noteID else { return }
        do {
            let note = try await APIClient().note(id: noteID, format: "markdown")
            serverDocument = try NoteDocument.fromServer(note.content)
            markdown = note.markdown ?? ""
            isLoading = false
        } catch {
            errorMessage = "Не удалось загрузить документ: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

#if DEBUG
enum MarkdownDocumentPreviewFixture {
    static let sample = """
    # Предпросмотр документа

    Обычный текст с **важным выделением** и [ссылкой](https://example.com).

    - Первый пункт списка
    - Второй пункт с несколькими словами

    > Цитата из документа — отдельным блоком.

    ```swift
    let status = "готово"
    print(status)
    ```

    | Проверка | Результат | Комментарий |
    | --- | --- | --- |
    | Перенос текста | Работает | Длинная ячейка для проверки переноса текста на несколько строк внутри одного столбца |
    | Следующая строка | Видна | Строка остаётся ниже предыдущей |
    | Литеральные знаки | Без потерь | \\*literal\\* |
    | Inline-код | Без потерь | `a|b` |
    """
}
#endif
