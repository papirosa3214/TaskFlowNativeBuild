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
        case type, doc, chars, header, align, rows, json, html, kind, component
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
        case "widget":
            // Новый формат — `component` (имя + данные); нет его — прежний `json`.
            if let props = (try? c.decodeIfPresent(AgentComponent.self, forKey: .component))?.propsJSON {
                self = .widget(props)
            } else {
                self = .widget(try c.decode(String.self, forKey: .json))
            }
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
/// разборе снимка с сервера, читается пейсером и экраном. Вытесняется
/// запись, которую дольше всех не читали (LRU): реплики активного хода
/// читаются на каждом кадре и поэтому не уходят, даже когда длинный ход
/// набрал много реплик (раньше 16 записей по порядку вставки — ранние реплики
/// показывали «Не удалось получить подготовленное содержимое»).
///
/// Запись можно привязать к области — идентичности живого хода
/// (`ChatLiveTurnIdentity`). Два хода с одинаковым или
/// пересекающимся текстом регистрируют разные блоки, и без области каждый из
/// них доставал чужую разметку: ответ одной сессии рисовался блоками другой
/// (владелец 14.11.2026). Теперь совпадение текста засчитывается только внутри
/// своей области, а запись без области видна только запросам без области —
/// чаты ролей работают как раньше.
public final class ChatLiveBlockRegistry: @unchecked Sendable {
    public static let shared = ChatLiveBlockRegistry()
    private let lock = NSLock()
    /// От давних к свежим: последний — самый недавно использованный.
    private var entries: [(text: String, scope: String?, blocks: [ChatLiveBlock])] = []
    private let limit: Int

    init(limit: Int = 64) {
        self.limit = max(1, limit)
    }

    public func register(_ blocks: [ChatLiveBlock], for text: String, scope: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.text == text && $0.scope == scope }
        entries.append((text, scope, blocks))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    public func blocks(for text: String, scope: String? = nil) -> [ChatLiveBlock]? {
        lock.lock(); defer { lock.unlock() }
        guard let index = entries.lastIndex(where: { $0.text == text && $0.scope == scope }) else {
            return nil
        }
        touch(index)
        return entries[entries.count - 1].blocks
    }

    /// Блок, чей исходный кусок начинается с показанного текста (пейсер
    /// показывает начало куска). Свежие реплики проверяются первыми.
    public func block(startingWith shown: String, scope: String? = nil) -> ChatLiveBlock? {
        guard !shown.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        for index in entries.indices.reversed() {
            guard entries[index].scope == scope else { continue }
            if let match = entries[index].blocks.last(where: { $0.source.hasPrefix(shown) && !$0.source.isEmpty }) {
                touch(index)
                return match
            }
        }
        return nil
    }

    /// Запись использована — в конец, к свежим. Вызывается под замком.
    private func touch(_ index: Int) {
        guard index != entries.count - 1 else { return }
        entries.append(entries.remove(at: index))
    }
}

/// Идентичность живого хода: у каждого хода свой номер, выданный один раз
/// при его начале, и он не пересчитывается из изменяемых полей.
///
/// Прежде область строилась из `sessionID` и `startedAt`: два хода в одну
/// секунду совпадали (`ISO8601Format` без долей), событие без `agent_start`
/// до `startedAt` давало `live`, а смена снимка переприсваивала `sessionID`
/// старому ходу. Запись блоков и чтение на экране берут теперь одну и ту же
/// строку `scope`, и переключение сессии уже не может связать запись с чужим
/// чтением (владелец 14.11.2026).
public struct ChatLiveTurnIdentity: Hashable, Sendable {
    /// Сессия, в которой начался ход: смена сессии — уже другой ход.
    public let sessionID: String?
    /// Номер хода: выдаётся сам собой, поэтому два одинаковых текста и две
    /// близкие по времени реплики не делят область.
    public let token: String

    public init(sessionID: String?, token: String = UUID().uuidString.lowercased()) {
        self.sessionID = sessionID
        self.token = token
    }

    /// Строка области разметки: неизменна на весь ход.
    public var scope: String { "turn:" + token }
}

public extension ChatServerBlock {
    /// Блоки из уже разобранного JSON (`JSONValue` модели, которой нужна
    /// `Codable`/`Hashable`): тот же формат, перекодированием.
    static func list(from values: [JSONValue]?) -> [ChatServerBlock]? {
        guard let values, let data = try? JSONEncoder().encode(values) else { return nil }
        return try? JSONDecoder().decode([ChatServerBlock].self, from: data)
    }

    /// Блоки из словаря `JSONSerialization` (данные виджета).
    static func list(fromFoundation value: Any?) -> [ChatServerBlock]? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode([ChatServerBlock].self, from: data)
    }

    /// Ключ кэша разбора — полное содержимое блока, а не его размеры.
    /// Прежний ключ живого куска знал у документа только число символов, у
    /// таблицы только размеры, а виджеты — `hashValue`: два разных payload с
    /// одинаковым исходным текстом делили одну запись кэша, и один ответ
    /// рисовался разметкой другого (владелец 14.11.2026).
    var cacheKey: String {
        switch self {
        case .doc(let doc, let chars):
            return "doc/\(chars)/" + Self.canonical(doc.foundationValue)
        case .table(let header, let align, let rows, let chars):
            let cells: [Any] = [header.map(\.foundationValue), align, rows.map { $0.map(\.foundationValue) }]
            return "table/\(chars)/" + Self.canonical(cells)
        case .widget(let json): return "widget/" + json
        case .structuredJSON(let json): return "json/" + json
        case .structuredJSONStreaming(let json): return "json-stream/" + json
        case .html(let html): return "html/" + html
        case .pending(let kind): return "pending/" + kind
        case .unknown: return "unknown"
        }
    }

    /// Запись значения без зависимости от порядка словаря и пробелов: одно и
    /// то же содержимое всегда даёт одну строку, разное — разные.
    static func canonical(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
        return text
    }
}
