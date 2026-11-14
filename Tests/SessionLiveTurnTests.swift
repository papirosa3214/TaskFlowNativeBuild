import XCTest

/// Живой ход сессии и её история — в той же модели, что ход роли в старой
/// комнате (`RoleChatLiveItem`): размышления, шаги инструментов с вызовом и
/// ответом, текст. Владелец 12.11.2026: «вернуть живой ход, который был в
/// старой версии… инструменты, DIF».
final class SessionLiveTurnTests: XCTestCase {
    private func obj(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }

    /// Размышление растёт во время хода одной мыслью, а текст её закрывает.
    /// С 13.11.2026 (`d780aa1c`, тонкий клиент) текст части готовит сервер
    /// полем `text` вместе с `blocks`: куски `delta` его не складывают.
    @objc func testThinkingDeltasGrowOneThoughtUntilText() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:])
        turn.apply(type: "assistant_thinking_delta",
                   payload: ["delta": .string("Смотрю "), "text": .string("Смотрю ")])
        turn.apply(type: "assistant_thinking_delta",
                   payload: ["delta": .string("файлы"), "text": .string("Смотрю файлы")])
        XCTAssertEqual(turn.items.count, 1, "куски одной мысли не должны её дублировать")
        guard turn.items.count == 1, case .thinking(let running) = turn.items[0] else {
            return XCTFail("нет размышления")
        }
        XCTAssertEqual(running.text, "Смотрю файлы")
        XCTAssertTrue(running.isRunning)

        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Гото"), "text": .string("Гото")])
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("во"), "text": .string("Готово")])
        XCTAssertEqual(turn.items.count, 2)
        guard turn.items.count == 2, case .thinking(let done) = turn.items[0] else {
            return XCTFail("нет размышления")
        }
        XCTAssertFalse(done.isRunning, "текст закрывает размышление")
        XCTAssertEqual(turn.items[1], .text("Готово"))
    }

    /// Кусок размышления без серверного текста не приклеиваем: показанное
    /// обязано совпадать с разметкой, иначе экран выдаёт «Не удалось получить
    /// подготовленное содержимое». Хвост придёт в `message_end`.
    @objc func testThinkingChunkWithoutServerTextIsNotGlued() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:])
        turn.apply(type: "assistant_thinking_delta",
                   payload: ["delta": .string("Смотрю "), "text": .string("Смотрю ")])
        turn.apply(type: "assistant_thinking_delta", payload: ["delta": .string("файлы")])
        XCTAssertEqual(turn.items.count, 1)
        guard turn.items.count == 1, case .thinking(let thought) = turn.items[0] else {
            return XCTFail("нет размышления")
        }
        XCTAssertEqual(thought.text, "Смотрю ", "кусок без разметки сервера не склеиваем")
        XCTAssertTrue(thought.isRunning)
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
        guard rows.count == 3 else { return XCTFail("строк ленты \(rows.count), ждали 3") }
        XCTAssertEqual(rows[0], .user(id: "u1", text: "Привет"))
        guard case .work(_, let items) = rows[1] else { return XCTFail("нет хода") }
        XCTAssertEqual(items.count, 2)
        guard items.count == 2, case .thinking(let thought) = items[0],
              case .step(let step) = items[1] else { return XCTFail("пунктов хода \(items.count), ждали 2") }
        XCTAssertEqual(thought.text, "Надо прочитать")
        XCTAssertFalse(thought.isRunning)
        XCTAssertEqual(step.id, "t1")
        XCTAssertEqual(step.detail, "a.md")
        XCTAssertEqual(step.status, .done)
        XCTAssertEqual(step.output, "# A")
        guard case .reply(let id, let reply) = rows[2] else { return XCTFail("нет ответа") }
        XCTAssertEqual(id, "a2")
        XCTAssertEqual(reply.text, "Прочитал")
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

    // MARK: - Расход, прерывание и тело шага в истории

    /// Токены, кэш и цена: Pi пишет расход в `message.usage` своими ключами
    /// (`cacheRead`, `cost.total`) — показываем тем же `RoleTurnUsage`.
    @objc func testUsageReadsPiKeys() {
        let entry: JSONValue = obj([
            "id": .string("e1"),
            "message": obj([
                "role": .string("assistant"),
                "model": .string("claude-sonnet-4-5"),
                "content": .array([obj(["type": .string("text"), "text": .string("Готово")])]),
                "usage": obj([
                    "input": .number(10950), "output": .number(144),
                    "cacheRead": .number(8000), "cacheWrite": .number(1200),
                    "cost": obj(["total": .number(0.042)]),
                ]),
                "stopReason": .string("stop"),
            ]),
        ])
        guard let usage = SessionFeed.usage(entry) else { return XCTFail("нет расхода") }
        XCTAssertEqual(usage.input, 10950)
        XCTAssertEqual(usage.output, 144)
        XCTAssertEqual(usage.cacheRead, 8000)
        XCTAssertEqual(usage.cacheWrite, 1200)
        XCTAssertEqual(usage.model, "claude-sonnet-4-5")
        XCTAssertEqual(usage.costUSD ?? 0, 0.042, accuracy: 0.0001)
        XCTAssertNil(usage.generationMs, "время генерации Pi не пишет — ток/с не выдумываем")
    }

    /// Старый снимок с сервера роли: подчёркивания и `cost_usd`.
    @objc func testUsageReadsServerKeys() {
        let entry: JSONValue = obj([
            "usage": obj([
                "input": .number(100), "output": .number(20),
                "cache_read": .number(10), "cache_write": .number(5),
                "cost_usd": .number(0.5),
            ]),
        ])
        guard let usage = SessionFeed.usage(entry) else { return XCTFail("нет расхода") }
        XCTAssertEqual(usage.cacheRead, 10)
        XCTAssertEqual(usage.cacheWrite, 5)
        XCTAssertEqual(usage.costUSD ?? 0, 0.5, accuracy: 0.0001)
    }

    /// Пустой расход и запись без `message` — строки расхода нет.
    @objc func testNoUsageNoRow() {
        XCTAssertNil(SessionFeed.usage(nil))
        XCTAssertNil(SessionFeed.usage(obj(["message": obj(["role": .string("user")])])))
        XCTAssertNil(SessionFeed.usage(obj(["message": obj([
            "usage": obj(["input": .number(0), "output": .number(0)]),
        ])])), "нулевой расход не показываем")
    }

    /// «Стоп» владельца в Pi — `stopReason: aborted`, текст сохранён частично.
    @objc func testStopAbortedIsOwnerInterrupt() {
        let stop = SessionFeed.stop(obj(["message": obj(["stopReason": .string("aborted")])]))
        XCTAssertEqual(stop?.interruption, .ownerInterrupt)
        XCTAssertEqual(stop?.isPartial, true)
    }

    /// Упавший ход — `stopReason: error`.
    @objc func testStopErrorIsFailure() {
        let stop = SessionFeed.stop(obj(["message": obj(["stopReason": .string("error")])]))
        XCTAssertEqual(stop?.interruption, .failed)
        XCTAssertEqual(stop?.isPartial, false)
    }

    /// Обычный конец ответа прерыванием не считается — значка нет.
    @objc func testNormalStopIsNotInterruption() {
        XCTAssertNil(SessionFeed.stop(obj(["message": obj(["stopReason": .string("stop")])])))
        XCTAssertNil(SessionFeed.stop(obj(["message": obj(["stopReason": .string("toolUse")])])))
        XCTAssertNil(SessionFeed.stop(obj(["message": obj(["role": .string("user")])])))
        XCTAssertNil(SessionFeed.stop(nil))
    }

    /// Тело шага достаётся повторным чтением снимка: вызов по id и его ответ.
    @objc func testStepBodyFromSnapshot() {
        let entries: [JSONValue] = [
            obj(["id": .string("a1"), "message": obj([
                "role": .string("assistant"),
                "content": .array([obj([
                    "type": .string("toolCall"), "id": .string("c1"), "name": .string("bash"),
                    "arguments": obj(["command": .string("ls -la")]),
                ])]),
            ])]),
            obj(["id": .string("a2"), "message": obj([
                "role": .string("toolResult"), "toolCallId": .string("c1"),
                "content": .array([obj(["type": .string("text"), "text": .string("out")])]),
            ])]),
        ]
        guard let step = SessionFeed.stepBody("c1", in: entries) else { return XCTFail("тела нет") }
        XCTAssertEqual(step.id, "c1")
        XCTAssertEqual(step.tool, "bash")
        XCTAssertEqual(step.detail, "ls -la")
        XCTAssertTrue(step.args?.contains("ls -la") == true)
        XCTAssertEqual(step.output, "out")
        XCTAssertEqual(step.status, .done)
    }

    /// Шага с таким id нет — загрузчик молчит, шторка откроется как есть.
    @objc func testStepBodyMissingIsNil() {
        XCTAssertNil(SessionFeed.stepBody("нет-такого", in: [
            obj(["message": obj(["role": .string("user"), "content": .string("привет")])]),
        ]))
    }

    /// В истории сервер говорит, что тела есть, но не присылает их — шаг
    /// помечается флагом, и лента спрашивает тело у загрузчика.
    @objc func testHistoryKeepsBodiesFlag() {
        let entries: [JSONValue] = [
            obj(["id": .string("a1"), "message": obj([
                "role": .string("assistant"),
                "content": .array([obj([
                    "type": .string("toolCall"), "id": .string("c1"), "name": .string("bash"),
                    "has_args": .bool(true), "has_output": .bool(true),
                ])]),
            ])]),
        ]
        guard case .work(_, let items)? = SessionFeed.rows(entries: entries).first,
              case .step(let step)? = items.first else { return XCTFail("нет шага") }
        XCTAssertNil(step.args, "тело не пришло — за него отвечает загрузчик")
        XCTAssertTrue(step.hasArgs)
        XCTAssertTrue(step.hasOutput)
    }

    @objc func testVoiceLinesStayMessages() {
        let entries: [JSONValue] = [
            obj(["id": .string("v1"), "type": .string("custom_message"), "customType": .string("taskflow.voice"),
                 "details": obj(["role": .string("assistant"), "text": .string("Сказал")])]),
        ]
        guard case .reply(let id, let reply)? = SessionFeed.rows(entries: entries).first else { return XCTFail() }
        XCTAssertEqual(id, "v1")
        XCTAssertEqual(reply.text, "Сказал")
    }

    // MARK: - Хвост ответа в `message_end` (14.11.2026)
    //
    // Сервер шлёт разметку не на каждый кусок (не чаще, чем раз в 300 мс) и
    // приносит точный последний текст части только в `message_end`. Хвост
    // обязан встать в пункт текста своего сообщения, даже если последним стал
    // размышление или шаг, и не должен терять текст, когда ни один кусок не
    // принёс серверного текста. Текст следующего сообщения не подменяет
    // предыдущий.

    private func textItems(_ turn: SessionLiveTurn) -> [String] {
        turn.items.compactMap { if case .text(let text) = $0 { return text } else { return nil } }
    }

    /// Разметка ответа тем же форматом, что готовит сервер: документ и его
    /// исходный кусок `source` (по нему живёт реестр блоков).
    private func replyBlocks(_ text: String) -> JSONValue {
        .array([obj([
            "type": .string("doc"),
            "doc": obj([
                "type": .string("doc"),
                "content": .array([obj([
                    "type": .string("paragraph"),
                    "content": .array([obj(["type": .string("text"), "text": .string(text)])]),
                ])]),
            ]),
            "chars": .number(Double(text.count)),
            "source": .string(text),
        ])])
    }

    /// Хвост после размышления: последний пункт хода — мысль, текст предыдущий.
    @objc func testMessageEndTailLandsWhenThinkingIsLast() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], sessionID: "s")
        turn.apply(type: "assistant_thinking_delta",
                   payload: ["delta": .string("Думаю"), "text": .string("Думаю")], sessionID: "s")
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Начало"), "text": .string("Начало")], sessionID: "s")
        turn.apply(type: "assistant_thinking_delta",
                   payload: ["delta": .string("Ещё мысль"), "text": .string("Ещё мысль")], sessionID: "s")
        turn.apply(type: "message_end",
                   payload: ["blocks": replyBlocks("Начало и хвост"), "text": .string("Начало и хвост")],
                   sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Начало и хвост"], "хвост текста потерян")
        guard let scope = turn.scope else { return XCTFail("нет области хода") }
        XCTAssertNotNil(ChatLiveBlockRegistry.shared.blocks(for: "Начало и хвост", scope: scope),
                        "финальная разметка не зарегистрирована")
    }

    /// Хвост перед шагом инструмента: текст был до вызова, `message_end`
    /// приходит, когда последним пунктом уже стоит шаг.
    @objc func testMessageEndTailLandsWhenStepIsLast() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], sessionID: "s")
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Сейчас"), "text": .string("Сейчас")], sessionID: "s")
        turn.apply(type: "tool_start",
                   payload: ["toolCallId": .string("c1"), "toolName": .string("bash"),
                             "args": obj(["command": .string("ls")])], sessionID: "s")
        turn.apply(type: "message_end",
                   payload: ["blocks": replyBlocks("Сейчас проверю хвост"),
                             "text": .string("Сейчас проверю хвост")], sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Сейчас проверю хвост"], "хвост перед шагом потерян")
        guard case .step = turn.items.last else { return XCTFail("шаг обязан остаться на месте") }
    }

    /// Ни один кусок не принёс серверного текста: ответ целиком есть только в
    /// `message_end` и обязан появиться.
    @objc func testMessageEndAddsReplyWhenDeltasCarriedNoServerText() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], sessionID: "s")
        turn.apply(type: "assistant_thinking_delta",
                   payload: ["delta": .string("Ду"), "text": .string("Ду")], sessionID: "s")
        turn.apply(type: "assistant_text_delta", payload: ["delta": .string("Нач")], sessionID: "s")
        turn.apply(type: "assistant_text_delta", payload: ["delta": .string("ало")], sessionID: "s")
        turn.apply(type: "message_end",
                   payload: ["blocks": replyBlocks("Начало и хвост"), "text": .string("Начало и хвост")],
                   sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Начало и хвост"], "ответ не попал в живой ход")
        XCTAssertEqual(turn.items.count, 2, "размышление и ответ — без заглушек и дублей")
    }

    /// Переподключение к середине хода: пунктов ещё нет, `message_end` с
    /// разметкой создаёт ответ, а не теряет его.
    @objc func testMessageEndCreatesReplyWhenTurnHasNoItems() {
        var turn = SessionLiveTurn()
        turn.apply(type: "message_end",
                   payload: ["blocks": replyBlocks("Ответ"), "text": .string("Ответ")],
                   sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Ответ"])
    }

    /// Два сообщения в одном ходе: текст второго не подменяет первый ни
    /// куском, ни хвостом; порядок пунктов сохраняется.
    @objc func testSecondMessageDoesNotOverwriteFirstAndKeepsOrder() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], sessionID: "s")
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Первый"), "text": .string("Первый"),
                             "blocks": replyBlocks("Первый")], sessionID: "s")
        turn.apply(type: "tool_start",
                   payload: ["toolCallId": .string("c9"), "toolName": .string("bash"),
                             "args": obj(["command": .string("ls")])], sessionID: "s")
        turn.apply(type: "tool_end",
                   payload: ["toolCallId": .string("c9"), "result": .object([:])], sessionID: "s")
        turn.apply(type: "message_end",
                   payload: ["blocks": replyBlocks("Первый полностью"),
                             "text": .string("Первый полностью")], sessionID: "s")
        // Второе сообщение после шага: свой кусок и свой хвост.
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Второй"), "text": .string("Второй"),
                             "blocks": replyBlocks("Второй")], sessionID: "s")
        turn.apply(type: "message_end",
                   payload: ["blocks": replyBlocks("Второй полностью"),
                             "text": .string("Второй полностью")], sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Первый полностью", "Второй полностью"],
                       "второй текст подменил или потерял первый")
        XCTAssertEqual(turn.items.count, 3, "порядок: ответ, шаг, второй ответ")
        guard turn.items.count == 3, case .text = turn.items[0], case .step = turn.items[1],
              case .text = turn.items[2] else {
            return XCTFail("порядок пунктов сломан: \(turn.items.count) пунктов")
        }
        guard let scope = turn.scope else { return XCTFail("нет области хода") }
        XCTAssertNotNil(ChatLiveBlockRegistry.shared.blocks(for: "Первый полностью", scope: scope),
                        "разметка первого ответа потеряна")
        XCTAssertNotNil(ChatLiveBlockRegistry.shared.blocks(for: "Второй полностью", scope: scope),
                        "разметка второго ответа потеряна")
    }

    /// Регрессия `f4f511a3`: текст, размышление и ещё текст в ОДНОМ сообщении.
    /// Сервер различает части ответа полем `contentIndex`; указатель на пункт
    /// текста нельзя переиспользовать, когда между кусками встало размышление,
    /// иначе второй текст подменяет первый и обе части теряются. Хвост
    /// `message_end` — текст ПОСЛЕДНЕЙ части, он дописывает вторую, а не первую.
    @objc func testSecondTextPartAfterThinkingKeepsBothParts() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], sessionID: "s")
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Первая"), "text": .string("Первая"),
                             "contentIndex": .number(0), "blocks": replyBlocks("Первая")],
                   sessionID: "s")
        turn.apply(type: "assistant_thinking_delta",
                   payload: ["delta": .string("Мысль"), "text": .string("Мысль"),
                             "contentIndex": .number(1)], sessionID: "s")
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Вторая"), "text": .string("Вторая"),
                             "contentIndex": .number(2), "blocks": replyBlocks("Вторая")],
                   sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Первая", "Вторая"], "второй текст подменил первый")
        XCTAssertEqual(turn.items.count, 3, "порядок: текст, размышление, текст")
        turn.apply(type: "message_end",
                   payload: ["text": .string("Вторая и хвост"),
                             "blocks": replyBlocks("Вторая и хвост"),
                             "message": obj([
                                "role": .string("assistant"),
                                "content": .array([
                                    obj(["type": .string("text"), "text": .string("Первая")]),
                                    obj(["type": .string("thinking"), "thinking": .string("Мысль")]),
                                    obj(["type": .string("text"), "text": .string("Вторая и хвост")]),
                                ]),
                             ])], sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Первая", "Вторая и хвост"], "хвост дописан не в свою часть")
        guard turn.items.count == 3, case .text = turn.items[0], case .thinking = turn.items[1],
              case .text = turn.items[2] else {
            return XCTFail("порядок пунктов сломан: \(turn.items.count) пунктов")
        }
        guard let scope = turn.scope else { return XCTFail("нет области хода") }
        XCTAssertNotNil(ChatLiveBlockRegistry.shared.blocks(for: "Вторая и хвост", scope: scope),
                        "финальная разметка второй части не зарегистрирована")
    }

    /// Хвост ДРУГОЙ части сообщения не подменяет показанную: часть, которую
    /// сервер держал конвертом, приходит целиком только в `message_end` и
    /// встаёт своим пунктом.
    @objc func testMessageEndTailOfAnotherPartDoesNotOverwriteShownText() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], sessionID: "s")
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Начало"), "text": .string("Начало"),
                             "contentIndex": .number(0), "blocks": replyBlocks("Начало")],
                   sessionID: "s")
        turn.apply(type: "message_end",
                   payload: ["text": .string("Вторая часть"),
                             "blocks": replyBlocks("Вторая часть"),
                             "message": obj([
                                "role": .string("assistant"),
                                "content": .array([
                                    obj(["type": .string("text"), "text": .string("Начало")]),
                                    obj(["type": .string("text"), "text": .string("Вторая часть")]),
                                ]),
                             ])], sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Начало", "Вторая часть"], "хвост подменил показанную часть")
    }

    /// `message_end` без разметки: показанное размеченное начало не подменяем
    /// голым текстом — иначе экран покажет «Не удалось получить содержимое».
    @objc func testMessageEndWithoutBlocksKeepsShownText() {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], sessionID: "s")
        turn.apply(type: "assistant_text_delta",
                   payload: ["delta": .string("Начало"), "text": .string("Начало"),
                             "blocks": replyBlocks("Начало")], sessionID: "s")
        turn.apply(type: "message_end", payload: ["text": .string("Начало и хвост")], sessionID: "s")
        XCTAssertEqual(textItems(turn), ["Начало"], "текст без разметки некуда положить")
    }

    // MARK: — Одна разметка в живом ходе и в истории (владелец 14.11.2026)

    /// Готовый ответ из нескольких блоков: показываем ВСЕ блоки, а не только
    /// первый. Прежний поиск «одного блока по началу текста» отдавал лишь
    /// первую часть — в конце хода виджет и хвост исчезали, историей ответ
    /// выглядел иначе (`ChatRichContent.replySegments`).
    @objc func testCompletedReplyKeepsEveryBlock() {
        let head = "Сейчас покажу сводку."
        let widget = "```widget\n{\"type\":\"summary\"}\n```"
        let text = head + "\n\n" + widget
        let blocks: JSONValue = .array([
            obj([
                "type": .string("doc"),
                "doc": obj([
                    "type": .string("doc"),
                    "content": .array([obj([
                        "type": .string("paragraph"),
                        "content": .array([obj(["type": .string("text"), "text": .string(head)])]),
                    ])]),
                ]),
                "chars": .number(Double(head.count)),
                "source": .string(head),
            ]),
            obj([
                "type": .string("widget"),
                "json": .string("{\"type\":\"summary\"}"),
                "source": .string(widget),
            ]),
        ])
        XCTAssertTrue(SessionLiveTurn.register(blocks, for: text, scope: "s1"), "разметка не легла в реестр")

        let segments = ChatRichContent.replySegments(shown: text, scope: "s1")
        XCTAssertEqual(segments?.count, 2, "в готовом ответе должны быть все блоки, включая виджет")
        guard let segments, segments.count == 2 else { return }
        guard case .widget = segments[1] else {
            return XCTFail("второй блок ответа потерялся: \(segments[1])")
        }
    }

    /// Незнакомый блок от нового сервера не уносит с собой остальные: раньше
    /// разбор всего списка падал целиком, текст оставался без разметки и не
    /// показывался вовсе.
    @objc func testUnknownBlockDoesNotDropTheRest() {
        let text = "Ответ"
        let blocks: JSONValue = .array([
            obj([
                "type": .string("doc"),
                "doc": obj([
                    "type": .string("doc"),
                    "content": .array([obj([
                        "type": .string("paragraph"),
                        "content": .array([obj(["type": .string("text"), "text": .string(text)])]),
                    ])]),
                ]),
                "chars": .number(Double(text.count)),
                "source": .string(text),
            ]),
            // Виджет без `json` и без известного `component`: такой блок
            // приложение разобрать не может.
            obj(["type": .string("widget"), "source": .string("```widget\n{}\n```")]),
        ])
        XCTAssertTrue(SessionLiveTurn.register(blocks, for: text, scope: "s2"),
                      "годный блок должен остаться, а не пропасть вместе с чужим")
        XCTAssertEqual(ChatLiveBlockRegistry.shared.blocks(for: text, scope: "s2")?.count, 1)
    }
}
