import Foundation

/// Готовые блоки сервера, адаптированные для нативного отображения.
enum ChatRichSegment: Equatable {
    /// Текст, уже разобранный сервером в блоки; `chars` — его длина для проявления.
    case document([NoteBlock], chars: Int)
    case table(ChatTable)
    case widget(String)
    case structuredJSON(String)
    case structuredJSONStreaming(String)
    case html(String)
    case pending(ChatPendingKind)
}

enum ChatPendingKind: Equatable {
    case widget
    case structuredJSON
    case html
}

struct ChatTable: Equatable {
    enum Alignment: Equatable { case leading, center, trailing }
    var header: [String]
    var alignments: [Alignment]
    var rows: [[String]]
    /// Ячейки, уже размеченные сервером; клиент разметку не вычисляет.
    var headerRuns: [[RichRun]]? = nil
    var rowRuns: [[[RichRun]]]? = nil

    var columnCount: Int { header.count }
}

enum ChatRichContent {
    /// Языки блоков кода, которые рисуются артефактом, а не кодом.
    static let htmlLanguages: Set<String> = ["html", "artifact"]
    static let widgetLanguages: Set<String> = ["widget", "tf-widget"]
    static let structuredJSONLanguages: Set<String> = ["tf-json"]

    /// Сколько символов текста в куске — для проявления хвоста идущего ответа.
    static func characterCount(_ segment: ChatRichSegment) -> Int {
        switch segment {
        case .document(_, let chars): return chars
        case .table(let table): return (table.header + table.rows.flatMap { $0 }).reduce(0) { $0 + $1.count }
        case .widget, .structuredJSON, .structuredJSONStreaming, .html, .pending: return 0
        }
    }
}

// MARK: - Блоки сервера → куски ответа

extension ChatRichContent {
    /// Готовые блоки сервера (`ChatServerBlock`) → куски для отрисовки. Текст
    /// не раскладывается: документ и ячейки приходят уже разобранными.
    static func segments(fromServer blocks: [ChatServerBlock], key: String) -> [ChatRichSegment] {
        if let cached = serverSegments.value(for: key) { return cached }
        let segments = segmentsUncached(fromServer: blocks)
        serverSegments.set(segments, for: key)
        return segments
    }

    /// Готовые сообщения не меняются: перевод блоков в куски — один раз на текст.
    private static let serverSegments = ParsedValueCache<[ChatRichSegment]>(limit: 64)

    static func segmentsUncached(fromServer blocks: [ChatServerBlock]) -> [ChatRichSegment] {
        blocks.compactMap { block in
            switch block {
            case .doc(let doc, let chars):
                guard let object = doc.foundationValue as? [String: Any] else { return nil }
                return .document(NoteDocument.decode(fromObject: object).blocks, chars: chars)
            case .table(let header, let align, let rows, _):
                let headerRuns = header.map(runs)
                let rowRuns = rows.map { $0.map(runs) }
                return .table(ChatTable(
                    header: headerRuns.map(plain),
                    alignments: align.map { $0 == "center" ? .center : $0 == "trailing" ? .trailing : .leading },
                    rows: rowRuns.map { $0.map(plain) },
                    headerRuns: headerRuns,
                    rowRuns: rowRuns))
            case .widget(let json): return .widget(json)
            case .structuredJSON(let json): return .structuredJSON(json)
            case .structuredJSONStreaming(let json): return .structuredJSONStreaming(json)
            case .html(let html): return .html(html)
            case .pending(let kind):
                switch kind {
                case "widget": return .pending(.widget)
                case "structured_json": return .pending(.structuredJSON)
                case "html": return .pending(.html)
                default: return nil
                }
            case .unknown: return nil
            }
        }
    }

    /// Живой ход: показанное начало реплики → блок сервера, обрезанный по
    /// открытой доле исходного текста. nil — блоков нет (старый сервер).
    static func liveSegments(shown: String) -> [ChatRichSegment]? {
        guard let live = ChatLiveBlockRegistry.shared.block(startingWith: shown) else { return nil }
        let full = segments(fromServer: [live.block], key: "live:" + live.source)
        guard live.isProse, case .document(let blocks, _)? = full.first else { return full }
        let fraction = live.source.isEmpty ? 1 : Double(shown.count) / Double(live.source.count)
        return [.document(truncated(blocks, fraction: fraction), chars: shown.count + 1)]
    }

    /// Начало документа длиной в долю `fraction` его видимого текста: целые
    /// блоки, затем последний — обрезанный по кускам текста.
    static func truncated(_ blocks: [NoteBlock], fraction: Double) -> [NoteBlock] {
        guard fraction < 1 else { return blocks }
        let total = blocks.reduce(0) { $0 + $1.plainText.count }
        var budget = Int((Double(total) * max(0, fraction)).rounded())
        var result: [NoteBlock] = []
        for block in blocks {
            guard budget > 0 else { break }
            let length = block.plainText.count
            if length <= budget || block.runs.isEmpty {
                result.append(block)
                budget -= length
                continue
            }
            var cut = block
            var runs: [RichRun] = []
            for run in block.runs {
                guard budget > 0 else { break }
                var piece = run
                if run.text.count > budget { piece.text = String(run.text.prefix(budget)) }
                budget -= piece.text.count
                runs.append(piece)
            }
            cut.runs = runs
            result.append(cut)
            break
        }
        return result
    }

    private static func runs(_ cell: JSONValue) -> [RichRun] {
        NoteDocument.decodeInline(cell.foundationValue as? [Any])
    }

    private static func plain(_ runs: [RichRun]) -> String {
        runs.map(\.text).joined()
    }
}
