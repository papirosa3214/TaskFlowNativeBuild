import Foundation

/// Ответ роли, разложенный на куски, которые рисуются по-разному
/// (владелец 01.10.2026: таблицы, виджеты и «артефакты прямо в окне чата»).
///
/// Разбор нарочно отдельный от `MarkdownParser`: тот общий с заметками, и
/// таблица или html-блок, собранные им, при сохранении заметки превратились
/// бы в плоский текст. Здесь только чтение ответа роли.
///
/// Куски:
///   • `markdown` — обычный текст, дальше его разбирает `MarkdownParser`;
///   • `table` — таблица GitHub-вида (`| a | b |` + строка `|---|---|`);
///   • `widget` — блок ```widget с JSON: нативная карточка (`ChatWidgetView`);
///   • `structuredJSON` — блок ```tf-json с конвертом для нативной отрисовки;
///   • `html` — блок ```html: живой интерактивный артефакт (`ChatHTMLView`);
///   • `pending` — такой блок ещё дописывается (идущий ответ), вместо сырого
///     JSON/HTML показываем заглушку.
enum ChatRichSegment: Equatable {
    case markdown(String)
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

    var columnCount: Int { header.count }
}

enum ChatRichContent {
    /// Языки блоков кода, которые рисуются артефактом, а не кодом.
    static let htmlLanguages: Set<String> = ["html", "artifact"]
    static let widgetLanguages: Set<String> = ["widget", "tf-widget"]
    static let structuredJSONLanguages: Set<String> = ["tf-json"]

    /// Кэш разложения ответа на куски.
    ///
    /// Во время проявления состояние публикуется каждые 16 мс (60 Гц), а сам
    /// текст ответа меняется раз в ~150 мс: без кэша один и тот же текст
    /// раскладывался заново на каждом кадре — копия строки плюс разбор по
    /// строкам. Живой текст лежит в одном слоте (нужен только последний
    /// разбор), готовые ответы — в общем кэше: их много, и они не меняются.
    private static let streamingSegments = LastValueCache<[ChatRichSegment]>()
    private static let finishedSegments = ParsedValueCache<[ChatRichSegment]>(limit: 16)

    /// Разложение ответа на куски: тот же текст — тот же результат.
    static func split(_ text: String, isStreaming: Bool = true) -> [ChatRichSegment] {
        if isStreaming {
            if let cached = streamingSegments.value(for: text) { return cached }
            let segments = splitUncached(text, isStreaming: true)
            streamingSegments.set(segments, for: text)
            return segments
        }
        if let cached = finishedSegments.value(for: text) { return cached }
        let segments = splitUncached(text, isStreaming: false)
        finishedSegments.set(segments, for: text)
        return segments
    }

    /// Разложение без кэша — точка сверки для теста: результат кэша обязан
    /// совпадать с результатом свежего разложения.
    static func splitUncached(_ text: String, isStreaming: Bool = true) -> [ChatRichSegment] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var segments: [ChatRichSegment] = []
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.markdown(joined))
            }
            buffer = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                // Конец блока — строка, начинающаяся с ```.
                var j = i + 1
                while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("```") { j += 1 }
                let closed = j < lines.count
                let body = lines[(i + 1)..<min(j, lines.count)].joined(separator: "\n")
                let special: ChatPendingKind? = htmlLanguages.contains(language)
                    ? .html
                    : widgetLanguages.contains(language) ? .widget
                    : structuredJSONLanguages.contains(language) ? .structuredJSON : nil
                if let special {
                    flush()
                    if !closed && isStreaming {
                        if special == .structuredJSON {
                            segments.append(.structuredJSONStreaming(body))
                        } else {
                            segments.append(.pending(special))
                        }
                    } else {
                        switch special {
                        case .html: segments.append(.html(body))
                        case .widget: segments.append(.widget(body))
                        case .structuredJSON: segments.append(.structuredJSON(body))
                        }
                    }
                    i = closed ? j + 1 : lines.count
                    continue
                }
                // Обычный код — целиком в текст, таблицы внутри не ищем.
                let end = closed ? j : lines.count - 1
                buffer.append(contentsOf: lines[i...end])
                i = end + 1
                continue
            }

            if i + 1 < lines.count, isTableRow(line), let alignments = separatorAlignments(lines[i + 1]) {
                let header = cells(line)
                if header.count == alignments.count {
                    flush()
                    var rows: [[String]] = []
                    var j = i + 2
                    while j < lines.count, isTableRow(lines[j]) {
                        var row = cells(lines[j])
                        if row.count < header.count { row += Array(repeating: "", count: header.count - row.count) }
                        rows.append(Array(row.prefix(header.count)))
                        j += 1
                    }
                    segments.append(.table(ChatTable(header: header, alignments: alignments, rows: rows)))
                    i = j
                    continue
                }
            }

            buffer.append(line)
            i += 1
        }
        flush()
        return segments
    }

    /// Строка таблицы — есть хотя бы одна `|` вне начала/конца или она
    /// обрамлена `|` с обеих сторон.
    static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        return trimmed.hasPrefix("|") || cells(trimmed).count > 1
    }

    /// Ячейки строки: без крайних `|`, с учётом экранированного `\|`.
    static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") { trimmed.removeLast() }
        var result: [String] = []
        var current = ""
        var escaped = false
        for ch in trimmed {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// Строка-разделитель `|:---|:---:|---:|` → выравнивания колонок.
    static func separatorAlignments(_ line: String) -> [ChatTable.Alignment]? {
        guard line.contains("-") else { return nil }
        let parts = cells(line)
        var result: [ChatTable.Alignment] = []
        for part in parts {
            let p = part.replacingOccurrences(of: " ", with: "")
            guard !p.isEmpty, p.allSatisfy({ $0 == "-" || $0 == ":" }), p.contains("-") else { return nil }
            let left = p.hasPrefix(":")
            let right = p.hasSuffix(":")
            result.append(left && right ? .center : right ? .trailing : .leading)
        }
        return result.isEmpty ? nil : result
    }

    /// Сколько символов текста в куске — для проявления хвоста идущего ответа.
    static func characterCount(_ segment: ChatRichSegment) -> Int {
        switch segment {
        case .markdown(let text): return text.count + 1
        case .table(let table): return (table.header + table.rows.flatMap { $0 }).reduce(0) { $0 + $1.count }
        case .widget, .structuredJSON, .structuredJSONStreaming, .html, .pending: return 0
        }
    }
}

/// Extracts the current `text` block from an incomplete JSON response without
/// treating the rest of the document as valid. The complete document is still
/// decoded normally when the stream ends.
enum ChatStructuredJSONStreamParser {
    private static let textType = try! NSRegularExpression(pattern: #""type"\s*:\s*"text""#)
    private static let textField = try! NSRegularExpression(pattern: #""text"\s*:\s*""#)

    static func partialText(in json: String) -> String? {
        let outputKey = json.range(of: #""output""#) ?? json.range(of: #""blocks""#)
        guard let outputKey,
              let arrayStart = json[outputKey.upperBound...].firstIndex(of: "[") else { return nil }
        let searchRange = NSRange(arrayStart..<json.endIndex, in: json)
        guard let typeMatch = textType.firstMatch(in: json, range: searchRange),
              let typeRange = Range(typeMatch.range, in: json),
              let fieldMatch = textField.firstMatch(in: json, range: NSRange(typeRange.upperBound..<json.endIndex, in: json)),
              let fieldRange = Range(fieldMatch.range, in: json) else { return nil }

        return decodeStringPrefix(in: json, openingQuote: json.index(before: fieldRange.upperBound))
    }

    private static func decodeStringPrefix(in json: String, openingQuote: String.Index) -> String? {
        guard json[openingQuote] == "\"" else { return nil }
        var cursor = json.index(after: openingQuote)
        var encoded = ""

        while cursor < json.endIndex {
            let character = json[cursor]
            if character == "\"" {
                return decodeJSONString(encoded)
            }
            if character == "\\" {
                let slash = cursor
                cursor = json.index(after: cursor)
                guard cursor < json.endIndex else { break }
                let escape = json[cursor]
                if escape == "u" {
                    cursor = json.index(after: cursor)
                    var digits = 0
                    while cursor < json.endIndex, digits < 4, json[cursor].isHexDigit {
                        cursor = json.index(after: cursor)
                        digits += 1
                    }
                    guard digits == 4 else { break }
                    encoded += String(json[slash..<cursor])
                } else if "\\\"/bfnrt".contains(escape) {
                    let end = json.index(after: cursor)
                    encoded += String(json[slash..<end])
                    cursor = end
                } else {
                    break
                }
                continue
            }
            guard character.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else { break }
            encoded.append(character)
            cursor = json.index(after: cursor)
        }

        return decodeJSONString(encoded)
    }

    private static func decodeJSONString(_ encoded: String) -> String? {
        let source = "\"\(encoded)\""
        guard let data = source.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }
}
