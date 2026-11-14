import XCTest

/// Живая разметка нового хода привязана к идентичности хода, а не только к
/// тексту реплики. Общий `ChatLiveBlockRegistry` искал блоки по тексту, поэтому
/// два параллельных ответа с одинаковым или пересекающимся текстом доставали
/// чужие блоки: ответ одной сессии рисовался
/// разметкой другой (владелец 14.11.2026).
///
/// Проверяются настоящие компоненты пути, а не копии: модель хода
/// (`SessionLiveTurn.apply`), общий реестр блоков (`ChatLiveBlockRegistry`) и
/// разбор на экране (`ChatRichContent.liveSegments` через
/// `SessionLiveReplyContent.prepared`). Идентичность — сессия и номер хода,
/// выданный один раз: ни секунда начала, ни изменяемый `sessionID` в неё не
/// входят. Ключ кэша куска — полное содержимое блока, а не его размеры.
///
/// Тесты, которым нужен явный `bind(sessionID:)` (смена снимка), собираются
/// стендом только на исправленном коде: `SESSION_TURN_BASE` исключает их при
/// прогоне на базовом SHA.
final class ChatLiveBlockScopeTests: XCTestCase {
    private var registry: ChatLiveBlockRegistry { ChatLiveBlockRegistry.shared }

    /// Вид серверного блока — в событии и в разметке одинаково.
    private enum Shape {
        /// Обычный текст как документ TipTap.
        case prose(String)
        /// Тот же видимый текст, но вторая часть размечена жирным:
        /// `chars` и `source` совпадают, payload — другой.
        case marked(String)
        case widget(String)
        /// Таблица: размеры и число символов те же, содержимое другое.
        case table(header: String, cell: String, chars: Int)
    }

    /// Ровно то, что экран сессии передаёт в `RoleReplyMarkdown`
    /// (`SessionLiveTurnView.itemView`, случай `.text`).
    private func preparedForScreen(_ shown: String, scope: String?) -> [ChatRichSegment]? {
        SessionLiveReplyContent.prepared(shown: shown, scope: scope)
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runJSON(_ text: String, bold: Bool = false) -> String {
        let marks = bold ? ",\"marks\":[{\"type\":\"bold\"}]" : ""
        return "{\"type\":\"text\",\"text\":\"\(escaped(text))\"\(marks)}"
    }

    /// Серверный блок как JSON — так его присылает сервер.
    private func blockJSON(_ shape: Shape) -> String {
        switch shape {
        case .prose(let text):
            let doc = "{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[\(runJSON(text))]}]}"
            return "{\"type\":\"doc\",\"doc\":\(doc),\"chars\":\(text.count),\"source\":\"\(escaped(text))\"}"
        case .marked(let text):
            let split = text.range(of: " ", options: .backwards)
            let head = split.map { String(text[text.startIndex..<$0.lowerBound]) } ?? text
            let tail = split.map { String(text[$0.upperBound...]) } ?? ""
            let doc = "{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[\(runJSON(head + " ")),\(runJSON(tail, bold: true))]}]}"
            return "{\"type\":\"doc\",\"doc\":\(doc),\"chars\":\(text.count),\"source\":\"\(escaped(text))\"}"
        case .widget(let source):
            return "{\"type\":\"widget\",\"json\":\"{\\\"title\\\":\\\"Активность\\\"}\",\"source\":\"\(escaped(source))\"}"
        case .table(let header, let cell, let chars):
            // Ячейка — список встроенных узлов, как у сервера.
            return "{\"type\":\"table\",\"header\":[[\(runJSON(header))]],\"align\":[\"leading\"],"
                + "\"rows\":[[[\(runJSON(cell))]]],\"chars\":\(chars),\"source\":\"| \(escaped(header)) |\"}"
        }
    }

    private func liveBlocks(_ shapes: [Shape]) -> [ChatLiveBlock] {
        let json = "[" + shapes.map(blockJSON).joined(separator: ",") + "]"
        guard let data = json.data(using: .utf8),
              let blocks = try? JSONDecoder().decode([ChatLiveBlock].self, from: data) else {
            XCTFail("разметка сервера не разобралась: \(json)")
            return []
        }
        return blocks
    }

    private func textNode(_ text: String, bold: Bool = false) -> SessionJSON {
        var node: [String: SessionJSON] = ["type": .string("text"), "text": .string(text)]
        if bold { node["marks"] = .array([.object(["type": .string("bold")])]) }
        return .object(node)
    }

    /// То же содержимое как значение события — `SessionJSON` модели хода.
    private func serverValue(_ shape: Shape) -> SessionJSON {
        switch shape {
        case .prose(let text), .marked(let text):
            var nodes: [SessionJSON] = [textNode(text)]
            if case .marked = shape, let split = text.range(of: " ", options: .backwards) {
                nodes = [textNode(String(text[text.startIndex..<split.lowerBound]) + " "),
                         textNode(String(text[split.upperBound...]), bold: true)]
            }
            let doc: SessionJSON = .object([
                "type": .string("doc"),
                "content": .array([.object(["type": .string("paragraph"), "content": .array(nodes)])]),
            ])
            return .object(["type": .string("doc"), "doc": doc,
                            "chars": .number(Double(text.count)), "source": .string(text)])
        case .widget(let source):
            return .object(["type": .string("widget"),
                            "json": .string("{\"title\":\"Активность\"}"),
                            "source": .string(source)])
        case .table(let header, let cell, let chars):
            return .object(["type": .string("table"),
                            "header": .array([.array([textNode(header)])]),
                            "align": .array([.string("leading")]),
                            "rows": .array([.array([.array([textNode(cell)])])]),
                            "chars": .number(Double(chars)),
                            "source": .string("| \(header) |")])
        }
    }

    /// Настоящее событие текста с разметкой сервера — то, что приходит из потока.
    private func textDelta(_ text: String, blocks shapes: [Shape]) -> [String: SessionJSON] {
        ["delta": .string(text), "text": .string(text), "blocks": .array(shapes.map(serverValue))]
    }

    private func visibleText(_ segments: [ChatRichSegment]?) -> String {
        (segments ?? []).map { segment in
            switch segment {
            case .document(let blocks, _): return blocks.map(\.plainText).joined()
            case .table(let table): return table.header.joined() + table.rows.flatMap { $0 }.joined()
            case .widget, .structuredJSON, .structuredJSONStreaming, .pending: return ""
            case .html(let html): return html
            }
        }.joined()
    }

    private let turnStart = Date(timeIntervalSince1970: 1_764_000_000)

    /// Один ход: начало и текст с разметкой — как события потока.
    private func turn(in session: String, text: String, blocks: [Shape],
                      at now: Date) -> SessionLiveTurn {
        var turn = SessionLiveTurn()
        turn.apply(type: "agent_start", payload: [:], now: now, sessionID: session)
        turn.apply(type: "assistant_text_delta", payload: textDelta(text, blocks: blocks),
                   now: now, sessionID: session)
        return turn
    }

    // MARK: — идентичность хода не зависит от секунды и от nil

    func testTwoTurnsInSameSecondKeepOwnBlocks() {
        let text = "Сводка за сутки готова, подробности ниже."
        let session = "identity-same-second"
        // Оба хода начались в одну секунду: в ISO8601 без долей это раньше
        // давало одну и ту же область.
        let first = turn(in: session, text: text, blocks: [.widget(text)], at: turnStart)
        let second = turn(in: session, text: text, blocks: [.prose(text)],
                          at: turnStart.addingTimeInterval(0.4))

        guard let firstScope = first.scope, let secondScope = second.scope else {
            return XCTFail("ход без области: запись блоков не совпадёт с чтением")
        }
        XCTAssertNotEqual(firstScope, secondScope, "два хода в одну секунду получили одну область")

        guard case .widget? = preparedForScreen(text, scope: firstScope)?.first else {
            return XCTFail("первый ход потерял свой виджет")
        }
        guard case .document? = preparedForScreen(text, scope: secondScope)?.first else {
            return XCTFail("второй ход получил чужую разметку")
        }
    }

    func testEventWithoutAgentStartBindsWriteToRead() {
        // Переподключение в середине хода: `agent_start` уже прошёл, приходит
        // только текст. Область должна появиться здесь же.
        let text = "Ответ без начала хода: разметка всё равно своя."
        var turn = SessionLiveTurn()
        turn.apply(type: "assistant_text_delta",
                   payload: textDelta(text, blocks: [.widget(text)]),
                   now: turnStart, sessionID: "identity-no-start")
        guard let scope = turn.scope else {
            return XCTFail("событие без agent_start не выдало идентичность хода")
        }
        XCTAssertEqual(registry.blocks(for: text, scope: scope)?.first?.source, text)
        guard case .widget? = preparedForScreen(text, scope: scope)?.first else {
            return XCTFail("запись и чтение без agent_start разошлись")
        }
    }

    // MARK: — одинаковый текст, разные ходы

    func testParallelTurnsWithSameTextKeepOwnBlocks() {
        let text = "Две карточки по одной задаче, текст совпал."
        let a = turn(in: "identity-parallel-a", text: text, blocks: [.prose(text)], at: turnStart)
        let b = turn(in: "identity-parallel-b", text: text, blocks: [.widget(text)], at: turnStart)

        guard let scopeA = a.scope, let scopeB = b.scope else { return XCTFail("нет области") }
        // Без области — ничего: разметка хода не утекает ни в роли, ни в историю.
        XCTAssertNil(registry.blocks(for: text), "запись с областью видна запросу без области")
        XCTAssertNil(registry.block(startingWith: text), "запись с областью видна запросу без области")

        guard case .document? = preparedForScreen(text, scope: scopeA)?.first else {
            return XCTFail("ход A потерял свой текстовый блок")
        }
        guard case .widget? = preparedForScreen(text, scope: scopeB)?.first else {
            return XCTFail("ход B потерял свой виджет")
        }
        XCTAssertEqual(visibleText(preparedForScreen(text, scope: scopeA)), text)
    }

    func testOverlappingTextTakesBlocksOfOwnTurn() {
        let short = "Сводка по проекту готова."
        let long = short + " Ещё два пункта в карточке."
        let a = turn(in: "identity-overlap-a", text: short, blocks: [.widget(short)], at: turnStart)
        let b = turn(in: "identity-overlap-b", text: long, blocks: [.prose(long)], at: turnStart)
        guard let scopeA = a.scope, let scopeB = b.scope else { return XCTFail("нет области") }

        // Куски пересекаются: `short` — начало `long`, а поиск идёт по началу.
        let shown = "Сводка по проекту"
        guard case .widget? = preparedForScreen(shown, scope: scopeA)?.first else {
            return XCTFail("ход A взял разметку соседа с пересекающимся текстом")
        }
        guard case .document? = preparedForScreen(shown, scope: scopeB)?.first else {
            return XCTFail("ход B потерял свой текстовый кусок")
        }
        XCTAssertNil(preparedForScreen(shown, scope: nil))
    }

    // MARK: — смена снимка (сессии)

    #if !SESSION_TURN_BASE
    func testSnapshotOfSameSessionKeepsTurn() {
        let text = "Ход продолжается, снимок той же сессии."
        var turn = self.turn(in: "identity-same-snapshot", text: text,
                             blocks: [.widget(text)], at: turnStart)
        let scope = turn.scope
        turn.bind(sessionID: "identity-same-snapshot")
        XCTAssertFalse(turn.isEmpty, "перечитывание снимка той же сессии сбросило ход")
        XCTAssertEqual(turn.scope, scope, "перечитывание снимка сменило область хода")
    }

    func testSnapshotOfAnotherSessionDropsOldTurn() {
        let text = "Ход прежней сессии не должен встать под чужой снимок."
        var turn = self.turn(in: "identity-switch-a", text: text,
                             blocks: [.widget(text)], at: turnStart)
        let oldScope = turn.scope

        turn.bind(sessionID: "identity-switch-b")
        XCTAssertTrue(turn.isEmpty, "элементы хода прежней сессии остались в новом снимке")
        XCTAssertNotEqual(turn.scope, oldScope, "область прежнего хода осталась у новой сессии")
        XCTAssertNil(preparedForScreen(text, scope: turn.scope),
                     "новая сессия прочитала разметку прежнего хода")

        // Событие новой сессии получает свою разметку, старый ход её не видит.
        turn.apply(type: "assistant_text_delta",
                   payload: textDelta(text, blocks: [.prose(text)]),
                   now: turnStart, sessionID: "identity-switch-b")
        guard case .document? = preparedForScreen(text, scope: turn.scope)?.first else {
            return XCTFail("ход новой сессии не прочитал свою разметку")
        }
        guard case .widget? = preparedForScreen(text, scope: oldScope)?.first else {
            return XCTFail("разметка прежнего хода подменилась")
        }
    }
    #endif

    // MARK: — ключ кэша: содержимое, а не размеры

    func testLiveCacheKeySeparatesDifferentPayloads() {
        let text = "Итог: два пункта"
        let plain = liveBlocks([.prose(text)])[0]
        let marked = liveBlocks([.marked(text)])[0]
        // Один и тот же видимый текст и число символов, разная разметка.
        XCTAssertEqual(plain.source, marked.source)
        if case .doc(_, let firstChars) = plain.block, case .doc(_, let secondChars) = marked.block {
            XCTAssertEqual(firstChars, secondChars, "у пары должен совпадать chars")
        } else {
            return XCTFail("документы не разобрались")
        }
        XCTAssertNotEqual(ChatRichContent.liveCacheKey(plain), ChatRichContent.liveCacheKey(marked),
                          "разный документ с тем же текстом получил один ключ кэша")

        let table = liveBlocks([.table(header: "Итог", cell: "два пункта", chars: 14)])[0]
        let otherTable = liveBlocks([.table(header: "Пункт", cell: "два итога!", chars: 14)])[0]
        XCTAssertNotEqual(ChatRichContent.liveCacheKey(table), ChatRichContent.liveCacheKey(otherTable),
                          "разные таблицы одинаковых размеров получили один ключ кэша")
    }

    func testLiveCacheDoesNotSwapMarkupOfSameText() {
        let text = "Итог: два пункта"
        // Две одинаковые по видимому тексту разметки, разные по маркам.
        let marked = liveBlocks([.marked(text)])[0]

        // Реестр — настоящий: один и тот же текст в разных областях.
        registry.register([marked], for: text, scope: "identity-cache-a")
        registry.register(liveBlocks([.prose(text)]), for: text, scope: "identity-cache-b")

        guard case .document(let first, _)? = preparedForScreen(text, scope: "identity-cache-a")?.first else {
            return XCTFail("размеченный документ не прочитался")
        }
        XCTAssertTrue(first.flatMap { $0.runs }.contains(where: \.bold),
                      "кэш вернул разметку другого payload: жирный кусок пропал")

        // Тот же текст, другая таблица: кэш не должен вернуть прежнюю.
        let one = liveBlocks([.table(header: "Итог", cell: "два пункта", chars: 14)])
        let two = liveBlocks([.table(header: "Пункт", cell: "два итога!", chars: 14)])
        registry.register(one, for: "| Итог |", scope: "identity-cache-table")
        guard case .table(let table)? = preparedForScreen("| Итог |", scope: "identity-cache-table")?.first else {
            return XCTFail("таблица не прочиталась")
        }
        XCTAssertEqual(table.header, ["Итог"])
        registry.register(two, for: "| Пункт |", scope: "identity-cache-table")
        guard case .table(let second)? = preparedForScreen("| Пункт |", scope: "identity-cache-table")?.first else {
            return XCTFail("вторая таблица не прочиталась")
        }
        XCTAssertEqual(second.header, ["Пункт"])
        XCTAssertEqual(second.rows, [["два итога!"]], "кэш вернул ячейки прежней таблицы")
    }

    // MARK: — чаты ролей и история: без области, как раньше

    func testUnscopedLookupsStayTextOnly() {
        let text = "Итог по роли: всё в порядке."
        let turn = turn(in: "identity-role", text: text, blocks: [.widget(text)], at: turnStart)
        XCTAssertNil(registry.blocks(for: text), "запрос без области увидел разметку хода сессии")

        registry.register(liveBlocks([.prose(text)]), for: text)
        XCTAssertEqual(registry.blocks(for: text)?.first?.source, text,
                       "чат роли потерял свою разметку без области")
        XCTAssertEqual(registry.block(startingWith: "Итог по роли")?.source, text,
                       "пейсер роли не нашёл блок без области")
        // Разметка хода сессии при этом не подменилась общей.
        guard case .widget? = preparedForScreen(text, scope: turn.scope)?.first else {
            return XCTFail("общая запись подменила разметку хода сессии")
        }
    }
}
