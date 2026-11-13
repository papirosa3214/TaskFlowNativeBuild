import XCTest

/// Живой ход сессии и её история — в той же модели, что ход роли в старой
/// комнате (`RoleChatLiveItem`): размышления, шаги инструментов с вызовом и
/// ответом, текст. Владелец 12.11.2026: «вернуть живой ход, который был в
/// старой версии… инструменты, DIF».
final class SessionLiveTurnTests: XCTestCase {
    private func obj(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }

    @objc func testThinkingDeltasGrowOneThoughtUntilText() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:])
        turn.apply(type: "assistant_thinking_delta", payload: ["delta": .string("Смотрю ")])
        turn.apply(type: "assistant_thinking_delta", payload: ["delta": .string("файлы")])
        guard case .thinking(let running)? = turn.items.first else { return XCTFail("нет размышления") }
        XCTAssertEqual(turn.items.count, 1)
        XCTAssertEqual(running.text, "Смотрю файлы")
        XCTAssertTrue(running.isRunning)

        turn.apply(type: "assistant_text_delta", payload: ["delta": .string("Гото")])
        turn.apply(type: "assistant_text_delta", payload: ["delta": .string("во")])
        XCTAssertEqual(turn.items.count, 2)
        guard case .thinking(let done) = turn.items[0] else { return XCTFail() }
        XCTAssertFalse(done.isRunning, "текст закрывает размышление")
        XCTAssertEqual(turn.items[1], .text("Готово"))
    }

    @objc func testToolStepCarriesCallAndAnswer() {
        var turn = SessionLiveTurn()
        turn.apply(type: "tool_start", payload: [
            "toolCallId": .string("c1"), "toolName": .string("bash"),
            "args": obj(["command": .string("ls -la")]),
        ])
        guard case .step(let running)? = turn.items.last else { return XCTFail("нет шага") }
        XCTAssertEqual(running.id, "c1")
        XCTAssertEqual(running.tool, "bash")
        XCTAssertEqual(running.detail, "ls -la")
        XCTAssertEqual(running.status, .running)
        XCTAssertTrue(running.args?.contains("ls -la") == true)

        turn.apply(type: "tool_update", payload: [
            "toolCallId": .string("c1"),
            "partialResult": obj(["content": .array([obj(["type": .string("text"), "text": .string("a.txt")])])]),
        ])
        guard case .step(let partial)? = turn.items.last else { return XCTFail() }
        XCTAssertEqual(partial.output, "a.txt")
        XCTAssertEqual(partial.status, .running)

        turn.apply(type: "tool_end", payload: [
            "toolCallId": .string("c1"), "isError": .bool(true),
            "result": obj(["content": .array([obj(["type": .string("text"), "text": .string("нет доступа")])])]),
        ])
        XCTAssertEqual(turn.items.count, 1)
        guard case .step(let ended)? = turn.items.last else { return XCTFail() }
        XCTAssertEqual(ended.status, .error)
        XCTAssertEqual(ended.output, "нет доступа")
    }

    @objc func testEditResultShowsDiff() {
        var turn = SessionLiveTurn()
        turn.apply(type: "tool_start", payload: [
            "toolCallId": .string("e1"), "toolName": .string("edit"),
            "args": obj(["path": .string("Sources/A.swift")]),
        ])
        turn.apply(type: "tool_end", payload: [
            "toolCallId": .string("e1"),
            "result": obj([
                "content": .array([obj(["type": .string("text"), "text": .string("Правка внесена")])]),
                "details": obj(["diff": .string("-old\n+new")]),
            ]),
        ])
        guard case .step(let step)? = turn.items.last else { return XCTFail() }
        XCTAssertEqual(step.detail, "Sources/A.swift")
        XCTAssertEqual(step.status, .done)
        XCTAssertTrue(step.output?.contains("-old\n+new") == true, "дифф правки виден в ответе шага")
    }

    @objc func testAgentStartClearsPreviousTurn() {
        var turn = SessionLiveTurn()
        turn.apply(type: "assistant_text_delta", payload: ["delta": .string("старое")])
        turn.apply(type: "agent_start", payload: [:])
        XCTAssertTrue(turn.items.isEmpty)
        XCTAssertNotNil(turn.startedAt)
    }

    @objc func testHistoryBecomesTurnsWithSteps() {
        let entries: [JSONValue] = [
            obj(["id": .string("u1"), "message": obj(["role": .string("user"), "content": .string("Привет")])]),
            obj(["id": .string("a1"), "message": obj(["role": .string("assistant"), "content": .array([
                obj(["type": .string("thinking"), "thinking": .string("Надо прочитать")]),
                obj(["type": .string("toolCall"), "id": .string("t1"), "name": .string("read"),
                     "arguments": obj(["path": .string("a.md")])]),
            ])])]),
            obj(["id": .string("r1"), "message": obj(["role": .string("toolResult"), "toolCallId": .string("t1"),
                "toolName": .string("read"), "isError": .bool(false),
                "content": .array([obj(["type": .string("text"), "text": .string("# A")])])])]),
            obj(["id": .string("a2"), "message": obj(["role": .string("assistant"), "content": .array([
                obj(["type": .string("text"), "text": .string("Прочитал")]),
            ])])]),
        ]
        let rows = SessionFeed.rows(entries: entries)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], .user(id: "u1", text: "Привет"))
        guard case .work(_, let items) = rows[1] else { return XCTFail("нет хода") }
        XCTAssertEqual(items.count, 2)
        guard case .thinking(let thought) = items[0], case .step(let step) = items[1] else { return XCTFail() }
        XCTAssertEqual(thought.text, "Надо прочитать")
        XCTAssertFalse(thought.isRunning)
        XCTAssertEqual(step.id, "t1")
        XCTAssertEqual(step.detail, "a.md")
        XCTAssertEqual(step.status, .done)
        XCTAssertEqual(step.output, "# A")
        guard case .reply(let id, let text, _) = rows[2] else { return XCTFail("нет ответа") }
        XCTAssertEqual(id, "a2")
        XCTAssertEqual(text, "Прочитал")
    }

    /// Модель отвечает текстом и следом тем же ответом конвертом в ```json —
    /// показываем конверт, сырой JSON не виден (кадр владельца 13.11.2026).
    @objc func testEnvelopeAfterProseIsFound() {
        let text = "Ответ словами.\n\n```json\n{\"schema_version\":1,\"ok\":true,\"output\":[{\"type\":\"text\",\"text\":\"Ответ\"}]}\n```"
        let json = SessionFeed.envelope(in: text)
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.hasPrefix("{") == true)
        XCTAssertTrue(json?.hasSuffix("}") == true)
        XCTAssertEqual(SessionFeed.envelope(in: "{\"schema_version\":1,\"output\":[]}"), "{\"schema_version\":1,\"output\":[]}")
        XCTAssertNil(SessionFeed.envelope(in: "Просто текст с ```json\n{\"a\":1}\n``` без конверта"))
    }

    @objc func testVoiceLinesStayMessages() {
        let entries: [JSONValue] = [
            obj(["id": .string("v1"), "type": .string("custom_message"), "customType": .string("taskflow.voice"),
                 "details": obj(["role": .string("assistant"), "text": .string("Сказал")])]),
        ]
        guard case .reply(let id, let text, _)? = SessionFeed.rows(entries: entries).first else { return XCTFail() }
        XCTAssertEqual(id, "v1")
        XCTAssertEqual(text, "Сказал")
    }
}
