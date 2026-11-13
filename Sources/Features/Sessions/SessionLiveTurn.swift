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
    private(set) var startedAt: Date?

    var isEmpty: Bool { items.isEmpty }

    /// Последний шаг ещё идёт — для грани кубика «инструмент».
    var hasRunningTool: Bool {
        if case .step(let step)? = items.last { return step.status == .running }
        return false
    }

    mutating func reset() {
        items = []
        startedAt = nil
    }

    mutating func apply(type: String, payload: [String: SessionJSON], now: Date = Date()) {
        let stamp = SessionFeed.stamp(now)
        switch type {
        case "agent_start":
            reset()
            startedAt = now
        case "assistant_thinking_delta":
            guard let delta = payload["delta"]?.sessionString, !delta.isEmpty else { return }
            if case .thinking(let thought)? = items.last, thought.isRunning {
                items[items.count - 1] = .thinking(RoleChatThinking(
                    id: thought.id, text: thought.text + delta, isRunning: true, startedAt: thought.startedAt))
            } else {
                items.append(.thinking(RoleChatThinking(
                    id: "thinking-\(items.count)", text: delta, isRunning: true, startedAt: stamp)))
            }
        case "assistant_text_delta":
            guard let delta = payload["delta"]?.sessionString, !delta.isEmpty else { return }
            closeThinking(at: stamp)
            if case .text(let text)? = items.last {
                items[items.count - 1] = .text(text + delta)
            } else {
                items.append(.text(delta))
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

    private mutating func closeThinking(at stamp: String) {
        guard case .thinking(let thought)? = items.last, thought.isRunning else { return }
        items[items.count - 1] = .thinking(RoleChatThinking(
            id: thought.id, text: thought.text, isRunning: false, startedAt: thought.startedAt, endedAt: stamp))
    }
}

/// История сессии строками ленты: реплика владельца, ход Помощника
/// (размышления и шаги — та же полоса «Действия», что в комнате) и ответ.
enum SessionFeedRow: Identifiable, Equatable {
    case user(id: String, text: String)
    case work(id: String, items: [RoleChatLiveItem])
    /// `blocks` — разметка ответа от сервера (`text_blocks`), если есть.
    case reply(id: String, text: String, blocks: SessionJSON?)

    var id: String {
        switch self {
        case .user(let id, _), .work(let id, _), .reply(let id, _, _): id
        }
    }
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
                            ? .reply(id: entryID, text: text, blocks: object["text_blocks"])
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
                    rows.append(.reply(id: entryID, text: replyText, blocks: object["text_blocks"]))
                }
            }
        }
        flush()
        return rows
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
