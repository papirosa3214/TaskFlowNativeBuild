import SwiftUI

/// Отображает только подготовленные сервером блоки; исходный текст не разбирает.
struct RoleReplyMarkdown: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.color == rhs.color && lhs.allowsCommands == rhs.allowsCommands && lhs.fade == rhs.fade && lhs.isStreaming == rhs.isStreaming && lhs.serverBlocks == rhs.serverBlocks && lhs.prepared == rhs.prepared && lhs.textGroup == rhs.textGroup
    }

    let text: String
    var color: Color = .tfChatText
    var allowsCommands = false
    /// Проявление хвоста у идущего ответа (30.09.2026); nil — готовый текст.
    var fade: RoleTextFade?
    var isStreaming = false
    /// Контекст сообщения для отметок checklist-виджета (карточка 21842242).
    /// nil — ответ не из переписки (карточка задачи, превью): виджет рисуется,
    /// но отметка никуда не уходит. В сравнении (`==`) не участвует: ключи и
    /// отправка привязаны к сообщению, а не к тексту куска.
    var checklist: ChecklistSyncContext? = nil
    /// Ответ, уже разобранный сервером (26.10.2026): есть — рисуем блоки и
    /// текст сам не раскладываем; nil означает отсутствие подготовленных данных.
    var serverBlocks: [ChatServerBlock]? = nil
    /// Куски, уже собранные из блоков сервера (живой ход: блок, обрезанный по
    /// открытой части). Есть — текст не раскладывается.
    var prepared: [ChatRichSegment]? = nil
    /// Рассуждения используют собственную группу внутри Markdown, а не внешний font.
    var textGroup: TFChatTypeGroup = .body
    /// Жирный читает «Подзаголовок» — без этого счётчика `.equatable()` не
    /// перерисует ответ при смене ступени в настройках.
    @AppStorage(TFTypeScale.revisionKey) private var typeRevision = 0

    var body: some View {
        let _ = typeRevision
        let segments = prepared
            ?? serverBlocks.map { ChatRichContent.segments(fromServer: $0, key: text) }
            ?? []
        if segments.count == 1, case .document(let blocks, _) = segments[0] {
            documentBody(blocks)
        } else if segments.isEmpty {
            if !text.isEmpty {
                Text("Не удалось получить подготовленное содержимое")
                    .foregroundStyle(Color.tfSub)
            }
        } else {
            // Таблицы, виджеты и артефакты (владелец 01.10.2026) — своими
            // видами; текст между ними — как раньше. Хвост идущего ответа
            // проявляется по всему тексту, а не у каждого куска отдельно.
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                // Ключ куска — вид и порядковый номер среди своего вида, а не
                // номер в списке: когда посреди ответа встаёт таблица, абзац
                // за ней не пересоздаётся и не мигает (владелец 07.11.2026).
                let keys = Self.segmentKeys(segments)
                ForEach(Array(zip(keys, segments.indices)), id: \.0) { pair in
                    segmentView(segments[pair.1], fade: Self.tailFade(fade, isLast: pair.1 == segments.count - 1),
                                widgetKey: widgetKey(in: segments, at: pair.1))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Готовое сообщение — одна история на всё (печать сверху вниз).
            .roleReveal(fade?.revealsForward == true ? fade : nil)
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
        case .document(let blocks, _):
            documentBody(blocks, fade: fade)
        case .table(let table):
            ChatTableView(table: table, color: color, textGroup: textGroup)
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
                TFCard(padding: TFSpacing.md, surface: .dark, radius: TFRadius.xl) {
                    HStack(spacing: TFSpacing.sm) {
                        ProgressView()
                        Text("Собираю интерактив…")
                            .tfText(.body)
                            .foregroundStyle(Color.tfSub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Блоки текста — разобранные здесь или пришедшие с сервера готовыми.
    @ViewBuilder
    private func documentBody(_ parsed: [NoteBlock], fade: RoleTextFade?? = .none) -> some View {
        let fade: RoleTextFade? = fade ?? self.fade
        let blocks = Self.numbered(parsed)
        // Один `roleReveal` на всё дерево: иначе каждый `Text` заводит свою
        // историю и абзацы одной длины проявляются синхронно (владелец
        // 03.11.2026). Общая история слотов печатает сверху вниз.
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Индекс, а не id блока: парсер раздаёт новые UUID на каждый
            // разбор, а живой текст разбирается заново каждые 150 мс.
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, item in
                // Идущий ответ: проявляется только последний, растущий блок;
                // все выше уже напечатаны. Одна история на все блоки путала
                // их длины — от заголовков оставались первые буквы
                // (владелец 07.11.2026, скрин «Д / И / Итог»).
                blockView(item.block, number: item.number)
                    .roleReveal(fade?.revealsForward == false
                                ? Self.tailFade(fade, isLast: index == blocks.count - 1) : nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Готовое сообщение — одна история на всё дерево (печать сверху вниз).
        .roleReveal(fade?.revealsForward == true ? fade : nil)
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
    private func blockView(_ block: NoteBlock, number: Int) -> some View {
        switch block.kind {
        case .paragraph:
            inline(block)
        case .heading(let level):
            // Заголовок ответа — группа «Заголовок» шкалы чата; h1 чуть крупнее h2.
            inline(block, liftBold: false,
                   baseFont: .tfChat(.heading, weight: .semibold, scale: level <= 1 ? 1.15 : 1))
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
                inline(block)
                    .foregroundStyle(Color.tfSub)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .codeBlock(let language):
            if language?.lowercased() == "plan" {
                ResolutionPlanBlock(plan: block.runs.map(\.text).joined())
            } else if allowsCommands && fade == nil && language?.lowercased() == "bash" {
                BashCommandBlock(command: block.runs.map(\.text).joined())
                    .id(block.runs.map(\.text).joined())
            } else {
            TFCard(padding: 0, surface: .dark, radius: TFRadius.md) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(block.runs.map(\.text).joined())
                        .font(.tfChat(textGroup == .thinking ? .thinking : .mono, design: .monospaced))
                        .foregroundStyle(color)
                        .textSelection(.enabled)
                        .padding(TFSpacing.md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        case .horizontalRule:
            Divider()
        case .table(let rows):
            StructuredDocumentBlocksView(blocks: [.table(rows)], chatGroup: textGroup == .thinking ? .thinking : nil)
        }
    }

    private func listRow(marker: Text, block: NoteBlock) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            marker
                .font(.tfChat(textGroup == .thinking ? .thinking : .body))
                .foregroundStyle(Color.tfSub)
                .frame(minWidth: 14, alignment: .trailing)
            inline(block)
        }
        .padding(.leading, CGFloat(block.level) * TFSpacing.lg)
    }

    /// `liftBold` — увеличивать ли жирное на ступень. В обычном тексте да,
    /// в заголовках нет: там жирное и так крупное, и лишний шаг вверх
    /// сбивал бы уровень (владелец 17.10.2026: жирное сливалось с текстом).
    private func inline(_ block: NoteBlock, liftBold: Bool = true, baseFont: Font? = nil) -> some View {
        Self.readableText(Self.pieces(for: block), color: color, liftBold: liftBold, baseFont: baseFont, textGroup: textGroup)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Кегли — из шкалы «Шрифт чата» (владелец 03.11.2026). Цвет у основного
    /// и жирного один; обычный чуть тише на 5%.
    private static func readableText(_ pieces: [RunPiece], color: Color, liftBold: Bool = true, baseFont: Font? = nil, textGroup: TFChatTypeGroup = .body) -> Text {
        let baseFont = textGroup == .thinking ? Font.tfChat(.thinking) : baseFont
        return pieces.reduce(Text("")) { result, piece in
            var text = Text(piece.attributed)
                .fontWeight(piece.bold ? .bold : nil)
                .foregroundColor(color)
            if let baseFont {
                text = text.font(piece.code ? baseFont.monospaced() : baseFont)
            } else if piece.code {
                text = text
                    .font(.tfChat(.mono, design: .monospaced))
                    .foregroundColor(color)
            } else if piece.bold, liftBold {
                text = text
                    .font(.tfChat(.emphasis, weight: .bold))
                    .foregroundColor(color)
            } else {
                text = text.font(.tfChat(.body))
                if liftBold {
                    text = text.foregroundColor(color.opacity(0.94))
                }
            }
            return Text("\(result)\(text)")
        }
    }

    /// Готовый кусок текста: разметка прогона и признаки начертания.
    struct RunPiece {
        let attributed: AttributedString
        let bold: Bool
        let code: Bool
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
        let built = block.runs.map {
            RunPiece(attributed: attributed([$0]), bold: $0.bold, code: $0.code)
        }
        runPieces.set(built, for: key)
        return built
    }

    /// Прогоны с марками → `AttributedString`: жирный/курсив/код/зачёркнутый
    /// через `inlinePresentationIntent` (его понимает `Text`), ссылка — `link`.
    static func attributed(_ runs: [RichRun], chatGroup: TFChatTypeGroup? = nil) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if run.strike { intent.insert(.strikethrough) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let chatGroup {
                let group = TFChatTypeGroup(rawValue: TypographyPreferences.chatRunGroup(
                    base: chatGroup.rawValue, bold: run.bold, code: run.code)) ?? chatGroup
                piece.font = .tfChat(group, weight: run.bold ? .bold : chatGroup == .heading ? .semibold : .regular)
            }
            if run.underline { piece.underlineStyle = .single }
            if run.highlight { piece.backgroundColor = Color.tfYellow.opacity(0.35) }
            if let href = run.linkHref, let url = URL(string: href) { piece.link = url }
            result += piece
        }
        return result
    }
}

extension RoleReplyMarkdown {
    /// Превью из готовых блоков сервера: первый блок текста, не длиннее
    /// `limit` символов. Ответ начинается не с текста — превью пустое. `key` — исходный текст для кэша блоков.
    static func previewSegments(of blocks: [ChatServerBlock], key: String, limit: Int = 220) -> [ChatRichSegment] {
        let segments = ChatRichContent.segments(fromServer: blocks, key: key)
        guard case .document(let document, _)? = segments.first, var first = document.first else { return [] }
        let length = first.plainText.count
        if length > limit, let cut = ChatRichContent.truncated([first], fraction: Double(limit) / Double(length)).first {
            first = cut
            first.runs.append(RichRun(text: "…"))
        }
        return [.document([first], chars: first.plainText.count)]
    }
}

/// Таблица из ответа роли (`| a | b |`): шапка, чередование строк,
/// выравнивание колонок из строки-разделителя, горизонтальная прокрутка для
/// широких таблиц. Ячейки понимают инлайн-разметку (**жирный**, `код`, ссылки).
struct ChatTableView: View {
    @AppStorage(TFTypeScale.revisionKey) private var typeRevision = 0
    let table: ChatTable
    var color: Color = .tfText
    var textGroup: TFChatTypeGroup = .body

    /// Шире — перенос строки внутри ячейки, а не бесконечная колонка.
    private static let maxCellWidth: CGFloat = 220
    /// Ниже — колонка с тикером всё равно читается (как в заметке).
    private static let minCellWidth: CGFloat = 44
    private static let paddingH = TFSpacing.sm
    private static let paddingV = TFSpacing.xs

    /// Выше — таблица листается внутри своего окошка, а не растягивает ленту.
    private static let maxHeight: CGFloat = 360
    @State private var bodyHeight: CGFloat = 0
    /// Ширины колонок — по содержимому и кеглю, один раз на всю жизнь таблицы.
    /// Измерение текста через NSString.size дорогое, а `LazyVStack` пересоздаёт
    /// вьюху на каждой прокрутке, поэтому кэш общий, а не `@State` (владелец
    /// 08.11.2026: «тонкий клиент, телефон не должен считать на кадр»).
    private static let widthCache = ParsedValueCache<[CGFloat]>(limit: 128)
    /// Кегль ячейки — из той же шкалы, что и `.tfText(.body)` (15, растёт от
    /// «Настройки → Шрифт»). Зашитое 15 разъехалось бы с нарисованным текстом.
    @ScaledMetric(relativeTo: .subheadline) private var bodySize: CGFloat = 15

    /// Ширины колонок для этой таблицы: из кэша или один раз мерятся здесь.
    /// Кегль входит в ключ — при смене «Настройки → Шрифт» таблица меряется заново.
    private func widths() -> [CGFloat] {
        let key = Self.cacheKey(table, size: bodySize)
        if let cached = Self.widthCache.value(for: key) { return cached }
        let measured = measuredWidths()
        Self.widthCache.set(measured, for: key)
        return measured
    }

    /// Ключ кэша — содержимое таблицы и кегль, без хеширования всего текста:
    /// строки склеиваются разделителями, которые в ячейках не встречаются.
    private static func cacheKey(_ table: ChatTable, size: CGFloat) -> String {
        var key = String(Int(size.rounded())) + "\u{1F}"
        key += table.header.joined(separator: "\u{1E}")
        for row in table.rows { key += "\u{1D}" + row.joined(separator: "\u{1E}") }
        return key
    }

    private func measuredWidths() -> [CGFloat] {
        let font = UIFont.systemFont(ofSize: bodySize)
        let headerFont = UIFont.systemFont(ofSize: bodySize, weight: .semibold)
        return table.header.indices.map { column in
            var widest: CGFloat = 0
            let cells = ([table.header] + table.rows).compactMap { row in
                row.indices.contains(column) ? row[column] : nil
            }
            for (index, text) in cells.enumerated() {
                let useFont = index == 0 ? headerFont : font
                let measured = text
                    .components(separatedBy: "\n")
                    .reduce(CGFloat.zero) { max($0, ($1 as NSString).size(withAttributes: [.font: useFont]).width) }
                widest = max(widest, ceil(measured))
            }
            return min(max(Self.minCellWidth, widest + Self.paddingH * 2 + 2), Self.maxCellWidth)
        }
    }

    // Окошко (владелец 14.10.2026): корпоративная тёмная подложка и рамка, как
    // у виджетов. Шапка закреплена (владелец 08.11.2026: «таблица должна ехать
    // по рельсам»): по горизонтали едет вся таблица вместе с шапкой, а
    // вертикально листаются только строки — шапка стоит на месте.
    var body: some View {
        let _ = typeRevision
        // Ширины берутся один раз за проход и раздаются всем строкам: считать
        // их внутри каждой ячейки — это повторный проход по всей таблице.
        let widths = widths()
        return TFCard(padding: 0, surface: .dark, radius: TFRadius.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow(widths)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                                bodyRow(row, rowIndex: rowIndex, isLast: rowIndex == table.rows.count - 1, widths: widths)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: [.vertical])
                    .frame(height: bodyHeight > 0 ? min(bodyHeight, Self.maxHeight) : nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                // Сетка как в заметке (владелец 08.11.2026: «таблица плавающая,
                // нет вертикальных линий»): вертикали и контур рисуются поверх
                // всей таблицы, чтобы линия была ровной на любой высоте строк.
                .overlay(alignment: .topLeading) { columnDividers(widths) }
                .overlay {
                    RoundedRectangle(cornerRadius: TFRadius.sm)
                        .strokeBorder(Color.tfFieldBorder, lineWidth: TFBorder.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
        }
    }

    private func headerRow(_ widths: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(table.header.enumerated()), id: \.offset) { column, title in
                cell(title, runs: headerRuns(column), isHeader: true, column: column, width: widths[column])
            }
        }
        .frame(minHeight: TFHitTarget.min, alignment: .top)
        // Шапка видна как шапка (владелец 08.11.2026: «тёмное, в наших цветах»):
        // тёмно-красная подложка-оттенок того же tfFieldBorder, а не серый.
        .background(Color.tfFieldBorder.opacity(0.45)) // design-system-guard: ignore — подложка только под шапкой, TFCard неприменим
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.tfFieldBorder).frame(height: TFBorder.width)
        }
    }

    private func bodyRow(_ row: [String], rowIndex: Int, isLast: Bool, widths: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                if column < widths.count {
                    cell(value, runs: rowRuns(rowIndex, column), column: column, width: widths[column])
                }
            }
        }
        .frame(minHeight: TFHitTarget.min, alignment: .top)
        // У последней строки своей нижней линии нет (владелец 08.11.2026):
        // контур таблицы и так замыкает её снизу, а своя линия читалась как
        // пустая строка с ячейками.
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.tfFieldBorder).frame(height: TFBorder.width)
            }
        }
    }

    /// Вертикальные разделители между колонками. Ширины те же, что у ячеек,
    /// поэтому линии совпадают с границами столбцов на любой высоте строк.
    private func columnDividers(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                Color.clear
                    .frame(width: width)
                    .overlay(alignment: .trailing) {
                        if index < widths.count - 1 {
                            Rectangle().fill(Color.tfFieldBorder).frame(width: TFBorder.width)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private func headerRuns(_ column: Int) -> [RichRun]? {
        guard let runs = table.headerRuns, runs.indices.contains(column) else { return nil }
        return runs[column]
    }

    private func rowRuns(_ row: Int, _ column: Int) -> [RichRun]? {
        guard let rows = table.rowRuns, rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        return rows[row][column]
    }

    private func cell(_ text: String, runs: [RichRun]?, chatGroup: TFChatTypeGroup = .body, isHeader: Bool = false, column: Int, width: CGFloat) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        // Ячейка приходит с сервера уже размеченной; локального разбора нет.
        let attributed = RoleReplyMarkdown.attributed(runs ?? [RichRun(text: text)], chatGroup: textGroup == .thinking ? .thinking : chatGroup)
        let content = Text(attributed)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
        return Group {
            if isHeader {
                content.tfChatText(.heading, weight: .semibold)
            } else {
                content.tfText(.body)
            }
        }
        .frame(width: max(1, width - Self.paddingH * 2), alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Self.paddingH)
        .padding(.vertical, Self.paddingV)
        .frame(width: width, alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
        .frame(minHeight: TFHitTarget.min, alignment: .topLeading)
    }


}

extension RoleReplyMarkdown {
    /// Устойчивые ключи кусков: «text-N» для текста, «block-N» для остального
    /// (недописанный блок и он же готовый — один ключ).
    static func segmentKeys(_ segments: [ChatRichSegment]) -> [String] {
        var text = 0, block = 0
        return segments.map { segment in
            switch segment {
            case .document:
                defer { text += 1 }
                return "text-\(text)"
            default:
                defer { block += 1 }
                return "block-\(block)"
            }
        }
    }
}

extension RoleReplyMarkdown {
    /// Хвост идущего ответа — только у последнего куска; у остальных та же
    /// модификация, но без анимации (вью не пересоздаётся, текст виден весь).
    static func tailFade(_ fade: RoleTextFade?, isLast: Bool) -> RoleTextFade? {
        guard var fade, !fade.revealsForward else { return fade }
        if !isLast { fade.isAnimating = false }
        return fade
    }
}
