import Foundation
#if canImport(NewChatCore)
import NewChatCore
/// JSON движка сессий: в приложении есть свой `JSONValue`, имена расходятся.
typealias SessionJSON = NewChatCore.JSONValue
#else
typealias SessionJSON = JSONValue
#endif

/// Идущий ход сессии в модели хода роли (`RoleChatLiveItem`): размышления,
/// шаги инструментов с вызовом и ответом, текст — в порядке событий. Рисуется
/// теми же компонентами, что живой ход в старой комнате чата (владелец
/// 12.11.2026: «вернуть живой ход, который был в старой версии… инструменты,
/// DIF… полностью перенести всю логику чата в новую версию»).
struct SessionLiveTurn: Equatable {
    private(set) var items: [RoleChatLiveItem] = []
    /// Часть текста ответа в ходе: пункт и номер части у сервера
    /// (`contentIndex`). Одно сообщение может содержать несколько текстовых
    /// частей, и номер части — единственный признак, по которому видно, что
    /// началась новая часть, а не продолжение прежней.
    private struct TextPart: Equatable {
        var index: Int
        var contentIndex: Int?
    }
    /// Пункт текста текущей части сообщения. Хвост из `message_end` кладётся в
    /// последнюю текстовую часть, даже если после текста пришло размышление
    /// или шаг инструмента: раньше
    /// хвост применялся только к последнему пункту и терялся (владелец
    /// 14.11.2026). Пункт переиспользуется только для той же
    /// части: когда между кусками встало размышление, сервер начинает новую
    /// часть (`contentIndex`), и её текст подменял первый (регрессия
    /// `f4f511a3`). На конце сообщения указатель сбрасывается.
    private var textPart: TextPart?
    private(set) var startedAt: Date?
    /// Идентичность хода: выдаётся один раз при его начале и хранится здесь.
    /// Раньше область пересчитывалась из `sessionID` и `startedAt` при каждом
    /// обращении: два хода в одну секунду получали одну область, событие без
    /// `agent_start` — `live`, а смена снимка переприсваивала сессию старому
    /// ходу. Теперь запись (`apply` → `scope`) и чтение на экране берут одну
    /// и ту же неизменную строку (владелец 14.11.2026).
    private(set) var identity: ChatLiveTurnIdentity?

    /// Сессия, которой принадлежит ход.
    var sessionID: String? { identity?.sessionID }

    /// Область живой разметки этого хода — та же строка, с которой
    /// регистрируются блоки, поэтому чтение не может промахнуться.
    var scope: String? { identity?.scope }

    var isEmpty: Bool { items.isEmpty }

    /// Последний шаг ещё идёт — для грани кубика «инструмент».
    var hasRunningTool: Bool {
        if case .step(let step)? = items.last { return step.status == .running }
        return false
    }

    /// Блоки сервера — в тот же реестр, что у живого хода ролей
    /// (`registerCurrentBlocks`): экран берёт их оттуда, текст не разбирает.
    /// `scope` — идентичность хода: без области запись остаётся видимой
    /// только запросам без области (история, чаты ролей). Возвращает `true`,
    /// если разметка легла в реестр: тогда текст пункта совпадёт с блоками и
    /// экран не покажет заглушку.
    @discardableResult
    static func register(_ value: SessionJSON?, for text: String, scope: String? = nil) -> Bool {
        guard let blocks = liveBlocks(value), !blocks.isEmpty else { return false }
        if let scope {
            ChatLiveBlockRegistry.shared.register(blocks, for: text, scope: scope)
        } else {
            // Без области — как в комнате роли: история и чаты ролей.
            ChatLiveBlockRegistry.shared.register(blocks, for: text)
        }
        return true
    }

    /// Блоки серверной разметки списком. Разбираем ПО ОДНОМУ: нестандартный
    /// блок (сервер новее приложения) не должен уносить с собой остальные —
    /// иначе ответ оставался без разметки и его хвост не показывался вовсе.
    static func liveBlocks(_ value: SessionJSON?) -> [ChatLiveBlock]? {
        guard let list = value?.foundationValue as? [Any], !list.isEmpty else { return nil }
        var blocks: [ChatLiveBlock] = []
        for item in list {
            guard let data = try? JSONSerialization.data(withJSONObject: item),
                  let block = try? JSONDecoder().decode(ChatLiveBlock.self, from: data) else { continue }
            blocks.append(block)
        }
        guard !blocks.isEmpty else { return nil }
        return blocks
    }

    /// То же разметкой без признака источника — для показа (`RoleReplyMarkdown`).
    static func blocks(_ value: SessionJSON?) -> [ChatServerBlock]? {
        liveBlocks(value)?.map(\.block)
    }

    /// Разметка размышлений из снимка: `thinking_blocks` — список {text, blocks}.
    static func registerThinking(_ value: SessionJSON?, for text: String, scope: String? = nil) {
        guard let list = value?.foundationValue as? [[String: Any]],
              let match = list.first(where: { ($0["text"] as? String) == text }),
              let blocks = match["blocks"] as? [Any],
              let data = try? JSONSerialization.data(withJSONObject: blocks),
              let decoded = try? JSONDecoder().decode([ChatLiveBlock].self, from: data), !decoded.isEmpty else { return }
        ChatLiveBlockRegistry.shared.register(decoded, for: text, scope: scope)
    }

    mutating func reset() {
        items = []
        textPart = nil
        startedAt = nil
        identity = nil
    }

    /// Открыта другая сессия: живой ход прежней сессии к этой не относится —
    /// его элементы и область сбрасываются, чтобы не показаться под её
    /// историей. Снимок той же сессии ход сохраняет (перечитывание, ответ
    /// голоса, повторный запрос).
    mutating func bind(sessionID: String?) {
        guard let sessionID, sessionID != self.sessionID else { return }
        reset()
        identity = ChatLiveTurnIdentity(sessionID: sessionID)
    }

    /// Новый ход: своя идентичность на каждый `agent_start`, даже если два
    /// хода начались в одну секунду.
    mutating func beginTurn(at now: Date) {
        let sessionID = identity?.sessionID
        reset()
        startedAt = now
        identity = ChatLiveTurnIdentity(sessionID: sessionID)
    }

    mutating func apply(type: String, payload: [String: SessionJSON], now: Date = Date(),
                        sessionID: String? = nil) {
        bind(sessionID: sessionID)
        if type == "agent_start" {
            beginTurn(at: now)
        } else if identity == nil {
            // Событие без `agent_start` (переподключение, середина хода):
            // номер выдаётся здесь же, и запись совпадёт с чтением.
            identity = ChatLiveTurnIdentity(sessionID: sessionID)
        }
        let stamp = SessionFeed.stamp(now)
        let scope = self.scope
        switch type {
        case "agent_start":
            // Ход начат выше: reset(), startedAt и новая идентичность.
            break
        case "assistant_thinking_delta":
            guard let delta = payload["delta"]?.sessionString, !delta.isEmpty else { return }
            // Тонкий клиент (владелец 13.11.2026): весь текст части и блоки
            // готовит сервер; кусок `delta` — только если сервер старый.
            let server = payload["text"]?.sessionString
            if case .thinking(let thought)? = items.last, thought.isRunning {
                // Размышление показывается только размеченным сервером: кусок
                // без разметки не дописываем, иначе текст не совпадёт с
                // разметкой и выйдет «Не удалось получить подготовленное
                // содержимое» (владелец 13.11.2026). Хвост придёт в message_end.
                guard let server else { return }
                let text = server
                items[items.count - 1] = .thinking(RoleChatThinking(
                    id: thought.id, text: text, isRunning: true, startedAt: thought.startedAt))
                Self.register(payload["blocks"], for: text, scope: scope)
            } else {
                let text = server ?? delta
                items.append(.thinking(RoleChatThinking(
                    id: "thinking-\(items.count)", text: text, isRunning: true, startedAt: stamp)))
                Self.register(payload["blocks"], for: text, scope: scope)
            }
        case "assistant_text_delta":
            guard let delta = payload["delta"]?.sessionString, !delta.isEmpty else { return }
            closeThinking(at: stamp)
            let server = payload["text"]?.sessionString
            // Кусок без разметки сервера не дописываем — текст должен
            // совпадать с размеченным (хвост придёт в message_end).
            guard let server else { return }
            // Сервер присылает номер части (`contentIndex`). Тот же номер и
            // пункт сразу за ним — продолжение части; иначе (между кусками
            // встало размышление или шаг) началась НОВАЯ часть, и её текст
            // обязан встать своим пунктом (регрессия `f4f511a3`).
            let part = payload["contentIndex"]?.sessionInt
            if let current = textPart, items.indices.contains(current.index),
               current.index == items.count - 1, case .text = items[current.index],
               part == nil || current.contentIndex == nil || current.contentIndex == part {
                items[current.index] = .text(server)
                textPart = TextPart(index: current.index, contentIndex: current.contentIndex ?? part)
            } else {
                // Новое сообщение или новая часть того же сообщения: свой
                // пункт, а не подмена текста предыдущего.
                items.append(.text(server))
                textPart = TextPart(index: items.count - 1, contentIndex: part)
            }
            Self.register(payload["blocks"], for: server, scope: scope)
        case "message_end":
            // Хвост ответа и размышления: сервер шлёт разметку не каждый раз,
            // а по абзацам; последняя — здесь (тонкий клиент без нагрева, 13.11.2026).
            if case .object(let thinking)? = payload["thinking"], let full = thinking["text"]?.sessionString,
               let index = items.lastIndex(where: { if case .thinking = $0 { return true } else { return false } }),
               case .thinking(let thought) = items[index] {
                items[index] = .thinking(RoleChatThinking(id: thought.id, text: full, isRunning: thought.isRunning,
                                                          startedAt: thought.startedAt))
                Self.register(thinking["blocks"], for: full, scope: scope)
            }
            // Сообщение кончилось: следующий текст — уже другое сообщение.
            let current = textPart
            textPart = nil
            guard let full = payload["text"]?.sessionString, !full.isEmpty else { return }
            // Без подготовленной разметки хвост класть некуда: экран ищет
            // блоки по тексту пункта, и голая строка встала бы заглушкой.
            // Показанное размеченное начало не подменяем.
            guard Self.register(payload["blocks"], for: full, scope: scope) else { return }
            // Контракт сервера: `text` здесь — весь текст ПОСЛЕДНЕЙ текстовой
            // части сообщения. Если это другая часть, чем показанная сейчас
            // (её держали конвертом, и куски не приходили), хвост встаёт своим
            // пунктом и не подменяет предыдущую часть.
            let tailPart = Self.lastTextPartIndex(payload["message"])
            if let current, items.indices.contains(current.index), case .text = items[current.index],
               tailPart == nil || current.contentIndex == nil || current.contentIndex == tailPart {
                items[current.index] = .text(full)
            } else {
                // Ни один кусок не принёс серверного текста — ответ целиком
                // есть только в `message_end`.
                items.append(.text(full))
            }
        case "tool_start":
            closeThinking(at: stamp)
            let id = payload["toolCallId"]?.sessionString ?? "tool-\(items.count)"
            let tool = payload["toolName"]?.sessionString ?? "tool"
            var step = RoleChatLiveStep(id: id, tool: tool, detail: SessionFeed.detail(payload["args"]),
                                        status: .running, startedAt: stamp)
            step.args = SessionFeed.pretty(payload["args"])
            if let index = stepIndex(id) { items[index] = .step(step) } else { items.append(.step(step)) }
        case "tool_update":
            guard let id = payload["toolCallId"]?.sessionString, let index = stepIndex(id),
                  case .step(var step) = items[index] else { return }
            step.output = SessionFeed.resultText(payload["partialResult"]) ?? step.output
            items[index] = .step(step)
        case "tool_end":
            guard let id = payload["toolCallId"]?.sessionString, let index = stepIndex(id),
                  case .step(let running) = items[index] else { return }
            let failed = payload["isError"]?.sessionBool ?? false
            var step = RoleChatLiveStep(id: running.id, tool: running.tool, detail: running.detail,
                                        status: failed ? .error : .done,
                                        startedAt: running.startedAt, endedAt: stamp)
            step.args = running.args
            step.output = SessionFeed.resultText(payload["result"]) ?? running.output
            items[index] = .step(step)
        default:
            break
        }
    }

    private func stepIndex(_ id: String) -> Int? {
        items.lastIndex { if case .step(let step) = $0 { return step.id == id } else { return false } }
    }

    /// Номер последней текстовой части сообщения `message_end`: сервер кладёт
    /// в `text` именно её (сырой `message.content` есть в том же payload).
    /// `nil` — сообщения нет, старый сервер или частей без типа `text`.
    static func lastTextPartIndex(_ message: SessionJSON?) -> Int? {
        guard case .object(let object)? = message, case .array(let parts)? = object["content"] else { return nil }
        return parts.lastIndex {
            guard case .object(let part) = $0 else { return false }
            return part["type"]?.sessionString == "text"
        }
    }

    private mutating func closeThinking(at stamp: String) {
        guard case .thinking(let thought)? = items.last, thought.isRunning else { return }
        items[items.count - 1] = .thinking(RoleChatThinking(
            id: thought.id, text: thought.text, isRunning: false, startedAt: thought.startedAt, endedAt: stamp))
    }
}

/// Реплика Помощника. Текст и разметка у неё от сервера и только от него:
/// снимок отдаёт `display_text`/`text_blocks`, живой `message_end` — `text`/
/// `blocks`. Телефон ничего не раскладывает заново, поэтому один и тот же
/// ответ в живом ходе и в истории выглядит одинаково.
struct SessionReply: Equatable {
    /// Запись снимка: из неё же быстрые ответы, расход, конверт, прерывание.
    var entry: SessionJSON?
    /// Текст для показа — серверный `display_text`, иначе сырой текст сообщения.
    var text: String
    /// Разметка сервера для этого же текста.
    var blocks: [ChatServerBlock]?

    init(entry: SessionJSON? = nil, text: String, blocks: [ChatServerBlock]? = nil) {
        self.entry = entry
        self.text = text
        self.blocks = blocks
    }

    /// Реплика из записи снимка: сервер уже подготовил и текст, и разметку.
    init(entry: SessionJSON, text: String) {
        self.init(entry: entry,
                  text: SessionFeed.serverDisplayText(entry) ?? text,
                  blocks: SessionFeed.serverTextBlocks(entry))
    }
}

/// История сессии строками ленты: реплика владельца, ход Помощника
/// (размышления и шаги — та же полоса «Действия», что в комнате) и ответ.
enum SessionFeedRow: Identifiable, Equatable {
    case user(id: String, text: String)
    case work(id: String, items: [RoleChatLiveItem])
    /// Реплика Помощника: текст и разметка — от сервера (см. `SessionReply`).
    case reply(id: String, reply: SessionReply)

    var id: String {
        switch self {
        case .user(let id, _), .work(let id, _), .reply(let id, _): id
        }
    }
}

/// Почему ответ не дописан: у Pi причина лежит в `stopReason` сообщения.
struct SessionStop: Equatable {
    let interruption: ChatMessageInterruption
    /// Текст сохранён недописанным — показываем как частичный.
    let isPartial: Bool
}

enum SessionFeed {
    /// Записи снимка → строки ленты. Шаги ищут свой ответ по `toolCallId`.
    static func rows(entries: [SessionJSON]) -> [SessionFeedRow] {
        var rows: [SessionFeedRow] = []
        var work: [RoleChatLiveItem] = []
        var workID: String?

        func flush() {
            if let workID, !work.isEmpty { rows.append(.work(id: workID, items: work)) }
            work = []
            workID = nil
        }

        for entry in entries {
            guard case .object(let object) = entry else { continue }
            let entryID = object["id"]?.sessionString ?? "entry-\(rows.count)-\(work.count)"
            // Реплика голосового разговора в сессии (сервер, 12.11.2026).
            if object["type"]?.sessionString == "custom_message",
               object["customType"]?.sessionString == "taskflow.voice",
               case .object(let details)? = object["details"],
               let text = details["text"]?.sessionString, !text.isEmpty {
                flush()
                rows.append(details["role"]?.sessionString == "assistant"
                            ? .reply(id: entryID, reply: SessionReply(entry: entry, text: text))
                            : .user(id: entryID, text: text))
                continue
            }
            let message: [String: SessionJSON]
            if case .object(let inner)? = object["message"] { message = inner } else { message = object }
            guard let role = message["role"]?.sessionString, role != "system" else { continue }

            switch role {
            case "user":
                flush()
                let text = plainText(message["content"])
                if !text.isEmpty { rows.append(.user(id: entryID, text: text)) }
            case "toolResult":
                let id = message["toolCallId"]?.sessionString
                let failed = message["isError"]?.sessionBool ?? false
                let output = resultText(.object(message)) ?? ""
                if let id, let index = work.lastIndex(where: {
                    if case .step(let step) = $0 { return step.id == id } else { return false }
                }), case .step(let call) = work[index] {
                    var step = RoleChatLiveStep(id: call.id, tool: call.tool, detail: call.detail,
                                                status: failed ? .error : .done,
                                                startedAt: call.startedAt, endedAt: call.endedAt)
                    step.args = call.args
                    step.output = output
                    work[index] = .step(step)
                }
            default:
                // Ответ Помощника: размышления и вызовы — в ход, текст —
                // отдельной строкой ответа после хода.
                var replyText = ""
                if case .array(let parts)? = message["content"] {
                    for (index, part) in parts.enumerated() {
                        guard case .object(let value) = part else { continue }
                        switch value["type"]?.sessionString ?? "" {
                        case "thinking":
                            let text = value["thinking"]?.sessionString ?? value["text"]?.sessionString ?? ""
                            // Разметка размышления из истории — с сервера (thinking_blocks).
                            SessionLiveTurn.registerThinking(object["thinking_blocks"], for: text)
                            guard !text.isEmpty else { continue }
                            if workID == nil { workID = entryID + "-work" }
                            work.append(.thinking(RoleChatThinking(
                                id: "\(entryID)-thinking-\(index)", text: text, isRunning: false)))
                        case "toolCall", "tool_use":
                            if workID == nil { workID = entryID + "-work" }
                            let arguments = value["arguments"] ?? value["input"]
                            var step = RoleChatLiveStep(
                                id: value["id"]?.sessionString ?? "\(entryID)-tool-\(index)",
                                tool: value["name"]?.sessionString ?? "tool",
                                detail: detail(arguments), status: .done)
                            step.args = pretty(arguments)
                            // Сервер говорит, что тела есть, а сами тела не прислал:
                            // шаг достанет их у загрузчика, когда владелец раскроет.
                            step.hasArgs = value["has_args"]?.sessionBool ?? false
                            step.hasOutput = value["has_output"]?.sessionBool ?? false
                            work.append(.step(step))
                        case "text":
                            replyText += value["text"]?.sessionString ?? ""
                        default:
                            continue
                        }
                    }
                } else if let text = message["content"]?.sessionString {
                    replyText = text
                }
                if !replyText.isEmpty {
                    flush()
                    rows.append(.reply(id: entryID, reply: SessionReply(entry: entry, text: replyText)))
                }
            }
        }
        flush()
        return rows
    }

    // MARK: Расход, прерывание, тело шага

    /// Сообщение записи: у Pi оно в `message`, у старого снимка — в корне.
    static func messageObject(_ entry: SessionJSON?) -> [String: SessionJSON]? {
        guard case .object(let object)? = entry else { return nil }
        if case .object(let inner)? = object["message"] { return inner }
        return object
    }

    /// Расход хода (владелец 13.11.2026: «токены вот эти надо»). Pi кладёт его
    /// в `message.usage` своими ключами (`cacheRead`, `cacheWrite`,
    /// `cost.total`), сервер роли — теми же, что `RoleTurnUsage` ждёт
    /// (`cache_read`, `cost_usd`): читаем оба набора. Времени генерации Pi не
    /// пишет, поэтому токена в секунду не будет — его не выдумываем.
    static func usage(_ entry: SessionJSON?) -> RoleTurnUsage? {
        guard let message = messageObject(entry),
              case .object(let raw)? = message["usage"] else { return nil }
        func number(_ keys: String...) -> Double? {
            for key in keys {
                if case .number(let value)? = raw[key] { return value }
                if let text = raw[key]?.sessionString, let value = Double(text) { return value }
            }
            return nil
        }
        let input = Int(number("input", "input_tokens") ?? 0)
        let output = Int(number("output", "output_tokens") ?? 0)
        guard input > 0 || output > 0 else { return nil }
        var cost: Double?
        if case .object(let money)? = raw["cost"], case .number(let total)? = money["total"] {
            cost = total
        }
        if cost == nil { cost = number("cost_usd", "costUSD") }
        return RoleTurnUsage(input: input, output: output,
                             cacheRead: Int(number("cacheRead", "cache_read") ?? 0),
                             cacheWrite: Int(number("cacheWrite", "cache_write") ?? 0),
                             costUSD: cost,
                             generationMs: nil,
                             model: message["model"]?.sessionString,
                             context: nil,
                             calls: nil)
    }

    /// Прерывание ответа: `aborted` — владелец нажал «стоп», `error` — ход
    /// упал, `length` — упёрлись в предел контекста. Обычный конец (`stop`,
    /// `toolUse`) прерыванием не считается — значка нет.
    static func stop(_ entry: SessionJSON?) -> SessionStop? {
        guard let message = messageObject(entry) else { return nil }
        let reasons = [message["stopReason"], message["stop_reason"], message["rawStopReason"]]
            .compactMap { $0?.sessionString }
        for reason in reasons {
            switch reason {
            case "aborted", "owner_interrupt":
                return SessionStop(interruption: .ownerInterrupt, isPartial: true)
            case "error", "failed":
                return SessionStop(interruption: .failed, isPartial: false)
            case "length", "max_tokens":
                return SessionStop(interruption: .other(reason), isPartial: true)
            default:
                continue
            }
        }
        return nil
    }

    /// Тело шага по его id из записей снимка: вызов и ответ инструмента.
    /// Нужно, когда снимок пришёл без тел (только флаги `has_args` и
    /// `has_output`): шторка шага спрашивает тело в момент раскрытия.
    static func stepBody(_ stepID: String, in entries: [SessionJSON]) -> RoleChatLiveStep? {
        var tool = "tool"
        var arguments: SessionJSON?
        var found = false
        var answer: String?
        var failed = false
        for entry in entries {
            guard let message = messageObject(entry) else { continue }
            let role = message["role"]?.sessionString
            if role == "toolResult" {
                guard message["toolCallId"]?.sessionString == stepID else { continue }
                failed = message["isError"]?.sessionBool ?? false
                answer = resultText(.object(message))
                continue
            }
            guard role == "assistant", case .array(let parts)? = message["content"] else { continue }
            for part in parts {
                guard case .object(let value) = part,
                      value["id"]?.sessionString == stepID,
                      ["toolCall", "tool_use"].contains(value["type"]?.sessionString ?? "") else { continue }
                tool = value["name"]?.sessionString ?? "tool"
                arguments = value["arguments"] ?? value["input"]
                found = true
            }
        }
        guard found || answer != nil else { return nil }
        var step = RoleChatLiveStep(id: stepID, tool: tool, detail: detail(arguments),
                                    status: failed ? .error : .done)
        step.args = pretty(arguments)
        step.output = answer
        return step
    }

    // MARK: Разбор вызова и ответа инструмента
    /// Короткая подпись шага: команда, путь, запрос — как у шага роли.
    static func detail(_ args: SessionJSON?) -> String? {
        guard case .object(let object)? = args else { return args?.sessionString }
        for key in ["command", "path", "file_path", "filePath", "pattern", "query", "url", "operation", "action"] {
            if let value = object[key]?.sessionString, !value.isEmpty {
                return value.split(separator: "\n", maxSplits: 1).first.map(String.init)
            }
        }
        return nil
    }

    /// Вызов целиком — читаемым JSON для шторки шага.
    static func pretty(_ value: SessionJSON?) -> String? {
        guard let value else { return nil }
        if let text = value.sessionString { return text }
        guard JSONSerialization.isValidJSONObject(value.sessionFoundation),
              let data = try? JSONSerialization.data(withJSONObject: value.sessionFoundation,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Ответ инструмента: текст его частей, а у правки — ещё и дифф.
    static func resultText(_ value: SessionJSON?) -> String? {
        guard let value else { return nil }
        if let text = value.sessionString { return text }
        guard case .object(let object) = value else { return pretty(value) }
        var parts: [String] = []
        let text = plainText(object["content"])
        if !text.isEmpty { parts.append(text) }
        if case .object(let details)? = object["details"], let diff = details["diff"]?.sessionString, !diff.isEmpty {
            parts.append(diff)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    static func plainText(_ content: SessionJSON?) -> String {
        switch content {
        case .string(let text)?: return text
        case .array(let parts)?:
            return parts.compactMap { part -> String? in
                guard case .object(let value) = part, value["type"]?.sessionString == "text" else { return nil }
                return value["text"]?.sessionString
            }.joined(separator: "\n")
        default: return ""
        }
    }

    /// Конверт ответа `{"schema_version":…}`: весь ответ или блок ```json
    /// где угодно в тексте (модель часто пишет ответ словами, а следом его же
    /// конвертом). Нет конверта — nil.
    static func envelope(in text: String) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("{"), body.contains("\"schema_version\"") { return body }
        var rest = Substring(text)
        while let open = rest.range(of: "```json") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "```") else { return nil }
            let inner = after[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.hasPrefix("{"), inner.contains("\"schema_version\"") { return inner }
            rest = after[close.upperBound...]
        }
        return nil
    }




    /// Поля, которые сервер готовит ответу сессии той же обработкой, что
    /// ответу роли (`display_text`, `quick_replies`, `role_envelope`,
    /// сервер 9e2df421). Есть — берём их, нет (старый сервер) — разбираем сами.
    static func serverDisplayText(_ entry: SessionJSON?) -> String? {
        guard case .object(let o)? = entry else { return nil }
        return o["display_text"]?.sessionString
    }

    static func serverTextBlocks(_ entry: SessionJSON?) -> [ChatServerBlock]? {
        guard case .object(let o)? = entry, let value = o["text_blocks"]?.foundationValue else { return nil }
        return ChatServerBlock.list(fromFoundation: value)
    }

    static func serverQuickReplies(_ entry: SessionJSON?) -> [String]? {
        guard case .object(let o)? = entry, let list = o["quick_replies"]?.foundationValue as? [Any] else { return nil }
        return Array(list.compactMap { $0 as? String }.prefix(3))
    }

    /// Второй слой ответа — только то, чего нет в `text_blocks`.
    ///
    /// Тонкий клиент (владелец 13.11.2026): текст, таблицы, виджеты, HTML и
    /// команды сервер собирает в `text_blocks` тем же разбором, что ответ роли
    /// (`structuredOutputText` → `chatBlocksCached`). Поэтому конверт целиком
    /// ко второму слою не годится: его таблица уже напечатана в блоках и
    /// появлялась дважды (владелец 14.11.2026, скрин IMG_9652). Из конверта
    /// остаются файлы (`artifacts`) и подсказка/вопрос — их в блоках нет.
    /// Запись без `text_blocks` (старый сервер) получает конверт как раньше,
    /// иначе пропали бы таблица и виджет.
    static func serverEnvelopeSecondLayer(_ entry: SessionJSON?) -> String? {
        guard serverTextBlocks(entry) != nil else { return serverEnvelopeExtras(entry) }
        guard case .object(let o)? = entry,
              var envelope = o["role_envelope"]?.foundationValue as? [String: Any] else { return nil }
        let artifacts = envelope["artifacts"] as? [Any] ?? []
        let hint = (envelope["next_hint"] as? String)?.isEmpty == false
        let needsHuman = (envelope["needs_human"] as? Bool) ?? false
        guard !artifacts.isEmpty || hint || needsHuman else { return nil }
        // Тело ответа и карточка ошибки живут в `text_blocks`; здесь пусто,
        // иначе второй раз печатается тот же ответ.
        envelope["output"] = []
        envelope["ok"] = true
        envelope.removeValue(forKey: "error")
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func serverEnvelopeExtras(_ entry: SessionJSON?) -> String? {
        guard case .object(let o)? = entry, var envelope = o["role_envelope"]?.foundationValue as? [String: Any] else { return nil }
        let output = (envelope["output"] as? [[String: Any]] ?? []).filter { ($0["type"] as? String) != "text" }
        let artifacts = envelope["artifacts"] as? [Any] ?? []
        guard !output.isEmpty || !artifacts.isEmpty else { return nil }
        envelope["output"] = output
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }


    static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

extension SessionJSON {
    var sessionString: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var sessionBool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Число без дробной части: `contentIndex` сервер шлёт числом JSON.
    var sessionInt: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var sessionFoundation: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.sessionFoundation)
        case .array(let value): return value.map(\.sessionFoundation)
        case .null: return NSNull()
        }
    }
}
