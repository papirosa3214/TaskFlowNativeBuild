import SwiftUI

/// Ответ роли с разметкой (владелец 27.09.2026, LOCK-230): в 1:1-чате ответ
/// идёт плоским текстом, как в окне Claude Code, и `**жирный**`, списки, код
/// показываются по-человечески, а не звёздочками. Разбор — существующий
/// `MarkdownParser` заметок (только чтение): второго парсера не заводим.
struct RoleReplyMarkdown: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.color == rhs.color && lhs.allowsCommands == rhs.allowsCommands && lhs.fade == rhs.fade && lhs.isStreaming == rhs.isStreaming
    }

    let text: String
    var color: Color = .tfText
    var allowsCommands = false
    /// Проявление хвоста у идущего ответа (30.09.2026); nil — готовый текст.
    var fade: RoleTextFade?
    var isStreaming = false
    /// Контекст сообщения для отметок checklist-виджета (карточка 21842242).
    /// nil — ответ не из переписки (карточка задачи, превью): виджет рисуется,
    /// но отметка никуда не уходит. В сравнении (`==`) не участвует: ключи и
    /// отправка привязаны к сообщению, а не к тексту куска.
    var checklist: ChecklistSyncContext? = nil

    var body: some View {
        let segments = ChatRichContent.split(text, isStreaming: isStreaming)
        if segments.count == 1, case .markdown = segments[0] {
            markdownBody(text)
        } else if segments.isEmpty {
            markdownBody(text)
        } else {
            // Таблицы, виджеты и артефакты (владелец 01.10.2026) — своими
            // видами; текст между ними — как раньше. Хвост идущего ответа
            // проявляется по всему тексту, а не у каждого куска отдельно.
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    segmentView(segment, fade: fade, widgetKey: widgetKey(in: segments, at: index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func charactersAfterSegments(_ segments: [ChatRichSegment]) -> [Int] {
        var result = Array(repeating: 0, count: segments.count)
        var sum = 0
        for index in segments.indices.reversed() {
            result[index] = sum
            sum += ChatRichContent.characterCount(segments[index])
        }
        return result
    }

    /// Номер блока виджета в сообщении — тем же порядком, каким их считает
    /// сервер: счёт идёт по блокам ```widget, а не по кускам ответа. Без
    /// контекста переписки (nil) не нужен.
    private func widgetKey(in segments: [ChatRichSegment], at segmentIndex: Int) -> String? {
        guard checklist != nil else { return nil }
        let widgetBlocks = segments.prefix(segmentIndex).filter {
            if case .widget = $0 { return true } else { return false }
        }
        return String(widgetBlocks.count)
    }

    @ViewBuilder
    private func segmentView(_ segment: ChatRichSegment, fade: RoleTextFade?, widgetKey: String?) -> some View {
        switch segment {
        case .markdown(let part):
            RoleReplyMarkdown(text: part, color: color, allowsCommands: allowsCommands, fade: fade)
        case .table(let table):
            ChatTableView(table: table, color: color)
        case .widget(let json):
            ChatWidgetView(json: json, widgetKey: widgetKey, checklist: checklist)
        case .structuredJSON(let json):
            ChatStructuredOutputView(json: json, checklist: checklist, allowsCommands: allowsCommands && fade == nil)
        case .structuredJSONStreaming(let json):
            ChatStructuredOutputView(json: json, isStreaming: true, checklist: checklist)
        case .html(let html):
            ChatHTMLView(html: html, allowsCommands: allowsCommands && fade == nil)
        case .pending(let kind):
            if kind == .widget {
                // Скелетон, а не «Готовлю виджет…»: визуальный язык §5.2 прямо
                // запрещает спиннер внутри виджета и требует геометрию итогового
                // блока, иначе при появлении данных карточка прыгает.
                WidgetSkeletonCard()
            } else if kind == .structuredJSON {
                WidgetCard(title: "Структурированный ответ") {
                    HStack(spacing: TFSpacing.sm) {
                        ProgressView()
                        Text("Собираю блоки ответа…")
                            .tfText(.body)
                            .foregroundStyle(Color.tfSub)
                    }
                }
            } else {
                HStack(spacing: TFSpacing.sm) {
                    ProgressView()
                    Text("Собираю интерактив…")
                        .tfText(.body)
                        .foregroundStyle(Color.tfSub)
                }
                .padding(TFSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.xl))
            }
        }
    }

    @ViewBuilder
    private func markdownBody(_ text: String) -> some View {
        // Живой текст растёт на каждом кадре проявления: разбираем заново
        // только последний блок, устойчивая часть — из кэша. Разбор всего
        // текста на каждом кадре стоил 110 мкс на ответ в 388 символов.
        let blocks = Self.numbered(isStreaming
            ? MarkdownParser.parseIncremental(text)
            : MarkdownParser.parse(text))
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Индекс, а не id блока: парсер раздаёт новые UUID на каждый
            // разбор, а живой текст разбирается заново каждые 150 мс.
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, item in
                blockView(item.block, number: item.number, fade: fade)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Сколько символов идёт после каждого блока — хвост проявляется по
    /// всему тексту, а не у каждого абзаца отдельно.
    static func charactersAfter(_ blocks: [NoteBlock]) -> [Int] {
        var result = Array(repeating: 0, count: blocks.count)
        var sum = 0
        for index in blocks.indices.reversed() {
            result[index] = sum
            sum += blocks[index].runs.reduce(0) { $0 + $1.text.count } + 1
        }
        return result
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
    private func blockView(_ block: NoteBlock, number: Int, fade: RoleTextFade?) -> some View {
        switch block.kind {
        case .paragraph:
            inline(block, fade: fade)
        case .heading(let level):
            inline(block, fade: fade, liftBold: false)
                .font(level <= 1 ? .title3.weight(.semibold) : .headline)
                .padding(.top, TFSpacing.xs)
        case .bulletItem:
            listRow(marker: Text("•"), block: block, fade: fade)
        case .orderedItem:
            listRow(marker: Text("\(number)."), block: block, fade: fade)
        case .taskItem(let checked):
            listRow(marker: Text(Image(systemName: checked ? "checkmark.square" : "square")), block: block, fade: fade)
        case .blockquote:
            HStack(alignment: .top, spacing: TFSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.tfStroke)
                    .frame(width: 3)
                inline(block, fade: fade)
                    .foregroundStyle(Color.tfSub)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .codeBlock(let language):
            if allowsCommands && fade == nil && language?.lowercased() == "bash" {
                BashCommandBlock(command: block.runs.map(\.text).joined())
                    .id(block.runs.map(\.text).joined())
            } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.runs.map(\.text).joined())
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(color)
                    .roleReveal(fade)
                    .textSelection(.enabled)
                    .padding(TFSpacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
            }
        case .horizontalRule:
            Divider()
        case .table:
            // Из текста таблицы парсер не собирает (только из заметок) —
            // таблицы ответа разбирает ChatRichContent. На всякий случай
            // показываем строки текстом.
            Text(block.runs.map(\.text).joined())
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
    }

    private func listRow(marker: Text, block: NoteBlock, fade: RoleTextFade?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            marker
                .foregroundStyle(Color.tfSub)
                .frame(minWidth: 14, alignment: .trailing)
            inline(block, fade: fade)
        }
        .padding(.leading, CGFloat(block.level) * TFSpacing.lg)
    }

    /// `liftBold` — увеличивать ли жирное на ступень. В обычном тексте да,
    /// в заголовках нет: там жирное и так крупное, и лишний шаг вверх
    /// сбивал бы уровень (владелец 17.10.2026: жирное сливалось с текстом).
    private func inline(_ block: NoteBlock, fade: RoleTextFade?, liftBold: Bool = true) -> some View {
        Self.readableText(Self.pieces(for: block), color: color, liftBold: liftBold)
            .roleReveal(fade)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Выделение — ТОЛЬКО весом, цвет у основного текста и жирного один
    /// (владелец 17.10.2026: «основной текст серый, жирный чуть ярже, но не
    /// вообще разные уровни текста»). Раньше основной текст рисовался как
    /// `color.opacity(0.65)` — это и был серый, и жирный на его фоне читался
    /// как другой уровень текста. Теперь оба `color`, различает вес.
    /// Вес задаётся на Text, чтобы сохранить унаследованный размер заголовка
    /// и Dynamic Type; разметка кода, ссылок и курсива остаётся у прогона.
    private static func readableText(_ pieces: [RunPiece], color: Color, liftBold: Bool = true) -> Text {
        pieces.reduce(Text("")) { result, piece in
            var text = Text(piece.attributed)
                .fontWeight(piece.bold ? .bold : nil)
                .foregroundColor(color)
            // Жирьём выделение не читалось: кегль был как у соседних слов,
            // и на телефоне выделение сливалось с текстом (владелец
            // 17.10.2026: «как будто бы и не выделяешь»). Поэтому жирное в
            // обычном тексте выделяется ВЕСОМ и яркостью, а не своим
            // кеглем: шаг `.body` (15 pt) в чате, где основной текст 17 pt,
            // делал «выделение» ещё и мельче соседей. Вес ставим последним —
            // иначе следующий `.font` его сбрасывает, и жирное рисуется
            // обычным начертанием.
            if piece.bold, liftBold {
                // Кегль не задаём: в чате основной текст 17 pt, а шаг `.body`
                // (15 pt) делал «выделение» ещё и мельче соседей. Вес, который
                // задан выше, после `.font` не доживал: выделение рисовалось
                // обычным начертанием.
                text = text.foregroundColor(color)
            } else if liftBold {
                // Обычный текст чуть тише жирного — буквально на 5%: полностью
                // приглушать нельзя, владелец уже возвращал серый основной текст
                // (17.10.2026), но на его фоне жирное снова сливалось. Теперь
                // разница есть и видна, и основной текст остаётся читаемым.
                text = text.foregroundColor(color.opacity(0.94))
            }
            return Text("\(result)\(text)")
        }
    }

    /// Готовый кусок текста: разметка прогона и признак жирного.
    struct RunPiece {
        let attributed: AttributedString
        let bold: Bool
    }

    /// Кэш готовых кусков текста по блоку.
    ///
    /// Тело ответа пересобирается на каждом кадре проявления (публикация
    /// состояния — каждые 16 мс, 60 Гц), а сборка `AttributedString` стоит
    /// ~2 мкс на прогон (замер 24.10.2026: 131 мкс на 60 прогонов) — это
    /// самая дорогая часть кадра проявления.
    ///
    /// Устойчивые блоки приходят из кэша разбора с теми же `id`, поэтому
    /// готовые куски переиспользуются; пересобирается только растущий хвост,
    /// у которого `id` каждый раз новый. Ключ — `id` блока: содержимое блока
    /// неизменно, поэтому ключ однозначно задаёт и куски.
    private static let runPieces = ParsedValueCache<[RunPiece]>(limit: 64)

    /// Куски текста блока — из кэша, если блок уже собирался.
    static func pieces(for block: NoteBlock) -> [RunPiece] {
        let key = block.id.uuidString
        if let cached = runPieces.value(for: key) { return cached }
        let built = block.runs.map { RunPiece(attributed: attributed([$0]), bold: $0.bold) }
        runPieces.set(built, for: key)
        return built
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

extension RoleReplyMarkdown {
    /// Короткая строка из текста роли для превью в строке списка: первый
    /// абзац до первого пустого места, без служебных блоков (таблица, виджет,
    /// JSON, HTML) — иначе превью в строке выросло бы на весь ответ.
    ///
    /// Разбор при этом общий: превью показывается тем же `RoleReplyMarkdown`,
    /// просто коротким куском текста, поэтому `**жирный**`, ссылки и код
    /// выглядят как в полном ответе, а не как сырые звёздочки.
    static func preview(of text: String, limit: Int = 220) -> String {
        var result = ""
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { break }          // служебный блок — не превью
            if line.isEmpty {
                if result.isEmpty { continue }            // пустые строки в начале
                break                                     // конец первого абзаца
            }
            result += result.isEmpty ? line : " " + line
            if result.count >= limit { break }
        }
        guard result.count > limit else { return result }
        return String(result.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Таблица из ответа роли (`| a | b |`): шапка, чередование строк,
/// выравнивание колонок из строки-разделителя, горизонтальная прокрутка для
/// широких таблиц. Ячейки понимают инлайн-разметку (**жирный**, `код`, ссылки).
struct ChatTableView: View {
    let table: ChatTable
    var color: Color = .tfText

    /// Шире — перенос строки внутри ячейки, а не бесконечная колонка.
    private static let maxCellWidth: CGFloat = 220

    /// Выше — таблица листается внутри своего окошка, а не растягивает ленту.
    private static let maxHeight: CGFloat = 360
    @State private var contentHeight: CGFloat = 0

    /// Одинаковая ширина ячейки во всех строках столбца. Длинное содержимое
    /// ограничивается сверху, чтобы переносить текст, а не раздувать таблицу.
    private var columnWidths: [CGFloat] {
        table.header.indices.map { column in
            let widest = ([table.header] + table.rows)
                .compactMap { $0.indices.contains(column) ? $0[column] : nil }
                .map(\.count)
                .max() ?? 0
            return min(max(88, CGFloat(widest) * 10 + TFSpacing.md * 2), Self.maxCellWidth)
        }
    }

    // Окошко (владелец 14.10.2026, по образцу): рамка стоит на месте,
    // таблица листается внутри неё в обе стороны.
    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, title in
                        cell(title, column: column, width: columnWidths[column])
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .background(Color.tfCard2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width)
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                            if column < columnWidths.count {
                                cell(value, column: column, width: columnWidths[column])
                                .tfText(.body)
                            }
                        }
                    }
                    .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.tfCard2.opacity(0.45))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.tfStroke.opacity(0.7)).frame(height: TFBorder.width)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .frame(height: contentHeight > 0 ? min(contentHeight, Self.maxHeight) : nil)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: TFRadius.lg).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
    }

    private func cell(_ text: String, column: Int, width: CGFloat) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        return Text(RoleReplyMarkdown.attributed(MarkdownParser.parseInline(text)))
            .foregroundStyle(color)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .frame(width: max(1, width - TFSpacing.md * 2), alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            .frame(width: width,
                   alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
    }


}

