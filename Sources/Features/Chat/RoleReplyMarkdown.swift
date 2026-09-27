import SwiftUI

/// Ответ роли с разметкой (владелец 27.09.2026, LOCK-230): в 1:1-чате ответ
/// идёт плоским текстом, как в окне Claude Code, и `**жирный**`, списки, код
/// показываются по-человечески, а не звёздочками. Разбор — существующий
/// `MarkdownParser` заметок (только чтение): второго парсера не заводим.
struct RoleReplyMarkdown: View {
    let text: String
    var color: Color = .tfText

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Индекс, а не id блока: парсер раздаёт новые UUID на каждый
            // разбор, а живой текст разбирается заново каждые 150 мс.
            ForEach(Array(Self.numbered(MarkdownParser.parse(text)).enumerated()), id: \.offset) { _, item in
                blockView(item.block, number: item.number)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Номер у пунктов нумерованного списка: подряд идущие на одном уровне.
    static func numbered(_ blocks: [NoteBlock]) -> [(block: NoteBlock, number: Int)] {
        var counters: [Int: Int] = [:]
        var result: [(NoteBlock, Int)] = []
        for block in blocks {
            if case .orderedItem = block.kind {
                let next = (counters[block.level] ?? 0) + 1
                counters[block.level] = next
                counters = counters.filter { $0.key <= block.level }
                result.append((block, next))
            } else {
                if !block.kind.isListItem { counters = [:] }
                result.append((block, 0))
            }
        }
        return result
    }

    @ViewBuilder
    private func blockView(_ block: NoteBlock, number: Int) -> some View {
        switch block.kind {
        case .paragraph:
            inline(block.runs)
        case .heading(let level):
            inline(block.runs)
                .font(level <= 1 ? .title3.weight(.semibold) : .headline)
                .padding(.top, TFSpacing.xs)
        case .bulletItem:
            listRow(marker: Text("•"), block: block)
        case .orderedItem:
            listRow(marker: Text("\(number)."), block: block)
        case .taskItem(let checked):
            listRow(marker: Text(Image(systemName: checked ? "checkmark.square" : "square")), block: block)
        case .blockquote:
            HStack(alignment: .top, spacing: TFSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.tfStroke)
                    .frame(width: 3)
                inline(block.runs)
                    .foregroundStyle(Color.tfSub)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .codeBlock:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.runs.map(\.text).joined())
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(TFSpacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        case .horizontalRule:
            Divider()
        case .table:
            // Из текста таблицы парсер не собирает (только из заметок) —
            // сюда не попадаем; на всякий случай показываем строки текстом.
            Text(block.runs.map(\.text).joined())
                .foregroundStyle(color)
        }
    }

    private func listRow(marker: Text, block: NoteBlock) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            marker
                .foregroundStyle(Color.tfSub)
                .frame(minWidth: 14, alignment: .trailing)
            inline(block.runs)
        }
        .padding(.leading, CGFloat(block.level) * TFSpacing.lg)
    }

    private func inline(_ runs: [RichRun]) -> some View {
        Text(Self.attributed(runs))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Прогоны с марками → `AttributedString`: жирный/курсив/код/зачёркнутый
    /// через `inlinePresentationIntent` (его понимает `Text`), ссылка — `link`.
    static func attributed(_ runs: [RichRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if run.strike { intent.insert(.strikethrough) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if run.underline { piece.underlineStyle = .single }
            if let href = run.linkHref, let url = URL(string: href) { piece.link = url }
            result += piece
        }
        return result
    }
}
