import Foundation

/// Живой ход роли дельтами (владелец 27.10.2026, по образцу протокола
/// AG-UI; формат — карточка TaskFlow 7b73b9c9, Linear MAK-137). Раньше сервер раз в 150 мс
/// слал `chats:live` с ходом целиком — весь текст заново на каждом кадре.
/// Теперь: `start` с заранее выданным номером сообщения, `patch` только с
/// изменениями, `end` после того, как ответ уже сохранён. `seq` растёт
/// строго на 1: пропуск — значит что-то потеряли, нужен снимок
/// `GET /chats/:id/live`.
public enum RoleChatLiveDelta: Decodable, Sendable, Equatable {
    case start(RoleChatLiveTurnState)
    case patch(chatID: String, userID: String, turnID: String, seq: Int, ops: [RoleChatLiveDeltaOp])
    case end(chatID: String, userID: String, turnID: String, seq: Int, messageID: String?)

    private enum CodingKeys: String, CodingKey {
        case type, ops, seq
        case chatID = "chat_id"
        case userID = "user_id"
        case turnID = "turn_id"
        case messageID = "message_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Ход шага карточки (`tasks:live:*`) идёт тем же форматом.
        let type = try container.decode(String.self, forKey: .type)
            .replacingOccurrences(of: "tasks:live:", with: "chats:live:")
        if type == "chats:live:start" {
            self = .start(try RoleChatLiveTurnState(from: decoder))
            return
        }
        let chatID = try container.decode(String.self, forKey: .chatID)
        let userID = try container.decode(String.self, forKey: .userID)
        let turnID = try container.decode(String.self, forKey: .turnID)
        let seq = try container.decode(Int.self, forKey: .seq)
        switch type {
        case "chats:live:patch":
            // Незнакомая операция (сервер новее клиента) не роняет пачку.
            let ops = try container.decode([RoleChatLiveDeltaOpSlot].self, forKey: .ops).compactMap(\.op)
            self = .patch(chatID: chatID, userID: userID, turnID: turnID, seq: seq, ops: ops)
        case "chats:live:end":
            self = .end(chatID: chatID, userID: userID, turnID: turnID, seq: seq,
                         messageID: try container.decodeIfPresent(String.self, forKey: .messageID))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "не событие хода: \(type)")
        }
    }

    var chatID: String {
        switch self {
        case .start(let state): return state.chatID
        case .patch(let chatID, _, _, _, _), .end(let chatID, _, _, _, _): return chatID
        }
    }

    var userID: String {
        switch self {
        case .start(let state): return state.userID
        case .patch(_, let userID, _, _, _), .end(_, let userID, _, _, _): return userID
        }
    }

    var turnID: String {
        switch self {
        case .start(let state): return state.turnID
        case .patch(_, _, let turnID, _, _), .end(_, _, let turnID, _, _): return turnID
        }
    }
}

public enum RoleChatLiveDeltaOp: Sendable, Equatable {
    case itemAdd(RoleChatLiveDeltaItem)
    case textAppend(itemID: String, text: String)
    case textReplace(itemID: String, text: String)
    case itemUpdate(itemID: String, fields: [String: RoleChatLiveJSON])
    case blocks(itemID: String, blocks: RoleChatLiveJSON)
    /// Последняя фраза размышлений; nil — роль больше не думает.
    case thinking(String?)
}

private struct RoleChatLiveDeltaOpSlot: Decodable {
    let op: RoleChatLiveDeltaOp?

    private enum CodingKeys: String, CodingKey {
        case op, item, text, fields, blocks, phrase
        case itemID = "item_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .op) {
        case "item_add": op = .itemAdd(try c.decode(RoleChatLiveDeltaItem.self, forKey: .item))
        case "text_append": op = .textAppend(itemID: try c.decode(String.self, forKey: .itemID), text: try c.decode(String.self, forKey: .text))
        case "text_replace": op = .textReplace(itemID: try c.decode(String.self, forKey: .itemID), text: try c.decode(String.self, forKey: .text))
        case "item_update": op = .itemUpdate(itemID: try c.decode(String.self, forKey: .itemID), fields: try c.decode([String: RoleChatLiveJSON].self, forKey: .fields))
        case "blocks": op = .blocks(itemID: try c.decode(String.self, forKey: .itemID), blocks: try c.decode(RoleChatLiveJSON.self, forKey: .blocks))
        case "thinking": op = .thinking(try c.decodeIfPresent(String.self, forKey: .phrase))
        default: op = nil
        }
    }
}

/// Элемент хода в дельтах: у каждого есть id (у текстовых кусков он
/// появился вместе с дельтами — в полном снимке его не было).
public struct RoleChatLiveDeltaItem: Decodable, Sendable, Equatable {
    public enum Kind: String, Decodable, Sendable { case text, step, thinking }

    let id: String
    let kind: Kind
    var text: String = ""
    var tool: String?
    var detail: String?
    var status: String?
    var args: String?
    var output: String?
    var startedAt: String?
    var endedAt: String?
    /// Блоки разметки, как их разложил сервер; приходят отдельной операцией
    /// только когда меняется их состав.
    var blocks: RoleChatLiveJSON? {
        didSet { blocksText = text }
    }
    /// Текст, при котором пришли блоки: дописанная проза их не обновляет.
    private var blocksText: String?
    /// Блоки, если они соответствуют нынешнему тексту; иначе nil — экран
    /// разбирает текст сам, как для старого сервера.
    var currentBlocks: RoleChatLiveJSON? { blocksText == text ? blocks : nil }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, tool, detail, status, args, output, blocks
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let rawKind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "step"
        kind = Kind(rawValue: rawKind) ?? .step
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        args = try c.decodeIfPresent(String.self, forKey: .args)
        output = try c.decodeIfPresent(String.self, forKey: .output)
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
        blocks = try c.decodeIfPresent(RoleChatLiveJSON.self, forKey: .blocks)
        if blocks != nil { blocksText = text }
    }

    mutating func merge(_ fields: [String: RoleChatLiveJSON]) {
        for (key, value) in fields {
            let string = value.string
            switch key {
            case "text": text = string ?? ""
            case "tool": tool = string
            case "detail": detail = string
            case "status": status = string
            case "args": args = string
            case "output": output = string
            case "started_at": startedAt = string
            case "ended_at": endedAt = string
            default: break
            }
        }
    }
}

/// Пауза хода роли на решение владельца (27.10.2026, аналог interrupt из
/// AG-UI). Роль задала вопрос `taskflow_ask_user_question` и ждёт: сервер
/// шлёт `chats:live:interrupt`, после ответа (или когда ждать перестали) —
/// `chats:live:resume`. Сам вопрос с кнопками приходит сообщением с полем
/// `question` и рисуется карточкой вопроса; ответ продолжает тот же ход.
public struct RoleChatLiveInterrupt: Decodable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case interrupt, resume }
    static let awaitingPhrase = "Ждёт вашего ответа"

    let kind: Kind
    let chatID: String
    let userID: String
    let questionID: String
    /// Сообщение с вопросом (только у паузы).
    let messageID: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case chatID = "chat_id"
        case userID = "user_id"
        case questionID = "question_id"
        case messageID = "message_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "chats:live:interrupt": kind = .interrupt
        case "chats:live:resume": kind = .resume
        case let type:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "не пауза хода: \(type)")
        }
        chatID = try c.decode(String.self, forKey: .chatID)
        userID = try c.decode(String.self, forKey: .userID)
        questionID = try c.decode(String.self, forKey: .questionID)
        messageID = try c.decodeIfPresent(String.self, forKey: .messageID)
    }
}

/// Идущий ход роли, собранный из дельт. Его же отдаёт снимок
/// `GET /chats/:id/live` (с `turn_id` и `seq`) — с него клиент продолжает
/// после переподключения.
public struct RoleChatLiveTurnState: Decodable, Sendable, Equatable {
    enum Outcome: Equatable {
        case applied
        /// Чужой ход или уже применённый номер — состояние не тронуто.
        case ignored
        /// Пропуск номера или операция над неизвестным элементом — состояние
        /// не тронуто, нужен снимок.
        case needsSnapshot
        /// Ход закончен; nil — ответа нет.
        case ended(messageID: String?)
    }

    let chatID: String
    let userID: String
    let turnID: String
    let messageID: String?
    let name: String
    let startedAt: String?
    let triggerMessageID: String?
    /// Шаг карточки (`tasks:live:*`); у чата — nil.
    let subtaskID: String?
    private(set) var seq: Int
    private(set) var items: [RoleChatLiveDeltaItem]
    /// Роль думает: последняя фраза; "" — думает, фразы нет; nil — не думает.
    private(set) var thinking: String?
    private(set) var isEnded = false
    /// Ход стоит на паузе на этом вопросе владельцу (`chats:live:interrupt`).
    private(set) var awaitingQuestionID: String?

    private enum CodingKeys: String, CodingKey {
        case name, seq, items, thinking
        case chatID = "chat_id"
        case userID = "user_id"
        case turnID = "turn_id"
        case messageID = "message_id"
        case startedAt = "started_at"
        case triggerMessageID = "trigger_message_id"
        case subtaskID = "subtask_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chatID = try c.decode(String.self, forKey: .chatID)
        userID = try c.decode(String.self, forKey: .userID)
        turnID = try c.decode(String.self, forKey: .turnID)
        messageID = try c.decodeIfPresent(String.self, forKey: .messageID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt)
        triggerMessageID = try c.decodeIfPresent(String.self, forKey: .triggerMessageID)
        subtaskID = try c.decodeIfPresent(String.self, forKey: .subtaskID)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        items = try c.decodeIfPresent([RoleChatLiveDeltaItem].self, forKey: .items) ?? []
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
    }

    /// Применить событие. Пачка операций применяется целиком или никак:
    /// при ошибке на середине состояние остаётся прежним.
    mutating func apply(_ event: RoleChatLiveDelta) -> Outcome {
        switch event {
        case .start:
            return .ignored
        case .patch(_, _, let turnID, let seq, let ops):
            switch check(turnID: turnID, seq: seq) {
            case .some(let outcome): return outcome
            case .none: break
            }
            var next = self
            for op in ops where !next.perform(op) { return .needsSnapshot }
            next.seq = seq
            self = next
            return .applied
        case .end(_, _, let turnID, let seq, let messageID):
            if let outcome = check(turnID: turnID, seq: seq) { return outcome }
            self.seq = seq
            isEnded = true
            thinking = nil
            return .ended(messageID: messageID)
        }
    }

    /// Пауза хода на вопрос и её снятие. Событие идёт вне счёта `seq`:
    /// оно не меняет состав хода, только то, что роль сейчас делает.
    /// false — событие не к этому ходу.
    mutating func apply(_ event: RoleChatLiveInterrupt) -> Bool {
        guard !isEnded, event.chatID == chatID, event.userID == userID else { return false }
        switch event.kind {
        case .interrupt:
            awaitingQuestionID = event.questionID
            thinking = RoleChatLiveInterrupt.awaitingPhrase
        case .resume:
            guard awaitingQuestionID == event.questionID else { return false }
            awaitingQuestionID = nil
            thinking = ""
        }
        return true
    }

    private func check(turnID: String, seq: Int) -> Outcome? {
        guard turnID == self.turnID, !isEnded, seq > self.seq else { return .ignored }
        return seq == self.seq + 1 ? nil : .needsSnapshot
    }

    private mutating func perform(_ op: RoleChatLiveDeltaOp) -> Bool {
        switch op {
        case .itemAdd(let item):
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item } else { items.append(item) }
            return true
        case .thinking(let phrase):
            thinking = phrase
            return true
        case .textAppend(let id, let text):
            return update(id) { $0.text += text }
        case .textReplace(let id, let text):
            return update(id) { $0.text = text }
        case .itemUpdate(let id, let fields):
            return update(id) { $0.merge(fields) }
        case .blocks(let id, let blocks):
            return update(id) { $0.blocks = blocks }
        }
    }

    private mutating func update(_ id: String, _ change: (inout RoleChatLiveDeltaItem) -> Void) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        change(&items[index])
        return true
    }
}

/// Произвольный JSON из дельт (поля `item_update`, блоки разметки) —
/// без зависимости от остального Core, чтобы обработчик проверялся сам.
public indirect enum RoleChatLiveJSON: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([RoleChatLiveJSON])
    case object([String: RoleChatLiveJSON])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([RoleChatLiveJSON].self) { self = .array(value) }
        else { self = .object(try c.decode([String: RoleChatLiveJSON].self)) }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
}

/// Строка «печатает…/работает с …» над лентой (27.10.2026): выводится из
/// хода дельтами, а не из отдельного события `chats:typing` — один поток,
/// как TOOL_CALL_START/END в AG-UI.
enum RoleChatActivity: Equatable {
    case typing
    case tool(String)
}

extension RoleChatLiveTurnState {
    /// nil — ход закончен.
    var activity: RoleChatActivity? {
        guard !isEnded else { return nil }
        if let last = items.last, last.kind == .step, (last.status ?? "running") == "running", let tool = last.tool {
            return .tool(tool)
        }
        return .typing
    }
}
