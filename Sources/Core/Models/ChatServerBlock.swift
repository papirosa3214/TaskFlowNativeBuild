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
/// (`ChatLiveBlockScope.session(_:turnStartedAt:)`). Два хода с одинаковым или
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

/// Идентичность живого хода: сессия и начало её хода. Сессия живёт долго, а
/// ходов в ней много, поэтому одной сессии мало: соседние ходы одного чата
/// тоже не должны смешиваться. Строка области строится одинаково на записи
/// (`SessionLiveTurn.apply`) и на чтении (`SessionLiveTurn.scope`) — обе берут
/// `Date.ISO8601Format()`, как и `RoleChatLiveTurn.startedAt`.
enum ChatLiveBlockScope {
    static func session(_ sessionID: String, turnStartedAt: Date?) -> String {
        sessionID + ":" + (turnStartedAt?.ISO8601Format() ?? "live")
    }
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
}
