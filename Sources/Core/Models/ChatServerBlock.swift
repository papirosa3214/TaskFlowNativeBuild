import Foundation

/// Кусок ответа в чате, уже разобранный сервером (`server/src/lib/chatBlocks.ts`,
/// 26.10.2026): клиент рисует его, а текст ответа сам не раскладывает.
///
/// • `doc` — обычный текст как документ TipTap (тот же формат, что у заметок);
/// • `table` — таблица: заголовок и строки ячеек TipTap, выравнивание колонок;
/// • `widget`, `structuredJSON`, `html` — блоки ```widget, ```tf-json, ```html;
/// • `structuredJSONStreaming`, `pending` — такой блок ещё дописывается;
/// • `unknown` — тип, которого этот клиент не знает (новый сервер): пропускаем.
public enum ChatServerBlock: Decodable, Sendable, Equatable {
    case doc(JSONValue, chars: Int)
    case table(header: [JSONValue], align: [String], rows: [[JSONValue]], chars: Int)
    case widget(String)
    case structuredJSON(String)
    case structuredJSONStreaming(String)
    case html(String)
    case pending(String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, doc, chars, header, align, rows, json, html, kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .type) {
        case "doc":
            self = .doc(try c.decode(JSONValue.self, forKey: .doc),
                        chars: try c.decodeIfPresent(Int.self, forKey: .chars) ?? 0)
        case "table":
            self = .table(header: try c.decode([JSONValue].self, forKey: .header),
                          align: try c.decodeIfPresent([String].self, forKey: .align) ?? [],
                          rows: try c.decode([[JSONValue]].self, forKey: .rows),
                          chars: try c.decodeIfPresent(Int.self, forKey: .chars) ?? 0)
        case "widget": self = .widget(try c.decode(String.self, forKey: .json))
        case "structured_json": self = .structuredJSON(try c.decode(String.self, forKey: .json))
        case "structured_json_streaming": self = .structuredJSONStreaming(try c.decode(String.self, forKey: .json))
        case "html": self = .html(try c.decode(String.self, forKey: .html))
        case "pending": self = .pending(try c.decode(String.self, forKey: .kind))
        default: self = .unknown
        }
    }
}

/// Блок живого хода с исходным куском текста (`source`, 26.10.2026): пейсер
/// проявляет исходный текст по словам, экран рисует блок, обрезанный по
/// открытой части. Сам текст на телефоне не раскладывается.
public struct ChatLiveBlock: Decodable, Sendable, Equatable {
    public let block: ChatServerBlock
    public let source: String

    private enum CodingKeys: String, CodingKey { case source }

    public init(block: ChatServerBlock, source: String) {
        self.block = block
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        block = try ChatServerBlock(from: decoder)
        source = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .source) ?? ""
    }

    /// Обычный текст проявляется по словам; виджеты, таблицы и артефакты — сразу.
    public var isProse: Bool {
        if case .doc = block { return true }
        return false
    }
}

/// Блоки текущих живых ходов по полному тексту реплики. Заполняется при
/// разборе снимка с сервера, читается пейсером и экраном. Хранит немного:
/// живых реплик единицы, старые вытесняются.
public final class ChatLiveBlockRegistry: @unchecked Sendable {
    public static let shared = ChatLiveBlockRegistry()
    private let lock = NSLock()
    private var entries: [(text: String, blocks: [ChatLiveBlock])] = []
    private let limit = 16

    public func register(_ blocks: [ChatLiveBlock], for text: String) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.text == text }
        entries.append((text, blocks))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    public func blocks(for text: String) -> [ChatLiveBlock]? {
        lock.lock(); defer { lock.unlock() }
        return entries.last { $0.text == text }?.blocks
    }

    /// Блок, чей исходный кусок начинается с показанного текста (пейсер
    /// показывает начало куска). Свежие реплики проверяются первыми.
    public func block(startingWith shown: String) -> ChatLiveBlock? {
        guard !shown.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        for entry in entries.reversed() {
            if let match = entry.blocks.last(where: { $0.source.hasPrefix(shown) && !$0.source.isEmpty }) { return match }
        }
        return nil
    }
}
