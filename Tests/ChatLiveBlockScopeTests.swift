import XCTest

/// Живая разметка нового хода привязана к идентичности хода (сессия + начало
/// хода), а не только к тексту реплики. Общий `ChatLiveBlockRegistry` искал
/// блоки по тексту, поэтому два параллельных ответа с одинаковым или
/// пересекающимся текстом доставали чужие блоки: ответ одной сессии рисовался
/// разметкой другой (владелец 14.11.2026).
///
/// Здесь две стороны одного свойства:
/// • реестр — запись с областью видна только своей области, запись без области
///   (чаты ролей, история) видна только запросам без области;
/// • путь экрана — `ChatRichContent.liveSegments(shown:scope:)`, то же выражение,
///   что `SessionLiveReplyContent.prepared(shown:scope:)` в живом ходе сессии.
final class ChatLiveBlockScopeTests: XCTestCase {
    private var registry: ChatLiveBlockRegistry { ChatLiveBlockRegistry.shared }

    /// Ровно то, что экран сессии передаёт в `RoleReplyMarkdown`
    /// (`SessionLiveTurnView.itemView`, случай `.text`).
    private func preparedForScreen(_ shown: String, scope: String?) -> [ChatRichSegment]? {
        SessionLiveReplyContent.prepared(shown: shown, scope: scope)
    }

    private func liveBlocks(_ json: String) -> [ChatLiveBlock] {
        guard let data = json.data(using: .utf8),
              let blocks = try? JSONDecoder().decode([ChatLiveBlock].self, from: data) else {
            XCTFail("разметка сервера не разобралась")
            return []
        }
        return blocks
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Обычный текст как документ TipTap — так его присылает сервер.
    private func proseBlocks(_ text: String) -> [ChatLiveBlock] {
        let body = escaped(text)
        return liveBlocks("[{\"type\":\"doc\",\"doc\":{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"\(body)\"}]}]},\"chars\":\(text.count),\"source\":\"\(body)\"}]")
    }

    /// Виджет с тем же исходным куском: текст совпадает, разметка другая.
    private func widgetBlocks(_ source: String) -> [ChatLiveBlock] {
        liveBlocks("[{\"type\":\"widget\",\"json\":\"{\\\"title\\\":\\\"Активность\\\"}\",\"source\":\"\(escaped(source))\"}]")
    }

    private func visibleText(_ segments: [ChatRichSegment]?) -> String {
        (segments ?? []).map { segment in
            switch segment {
            case .document(let blocks, _): return blocks.map(\.plainText).joined()
            case .table, .widget, .structuredJSON, .structuredJSONStreaming, .pending: return ""
            case .html(let html): return html
            }
        }.joined()
    }

    private let turnStart = Date(timeIntervalSince1970: 1_764_000_000)

    private func scope(_ session: String, _ startedAt: Date?) -> String {
        ChatLiveBlockScope.session(session, turnStartedAt: startedAt)
    }

    // MARK: — одинаковый текст, разные блоки

    func testParallelTurnsWithSameTextKeepOwnBlocks() {
        let text = "Сводка за сутки готова, подробности ниже."
        let a = scope("scope-test-a", turnStart)
        let b = scope("scope-test-b", turnStart)

        registry.register(proseBlocks(text), for: text, scope: a)
        registry.register(widgetBlocks(text), for: text, scope: b)

        // Реестр: у каждой области свои блоки.
        XCTAssertEqual(registry.blocks(for: text, scope: a)?.first?.block,
                       proseBlocks(text).first?.block)
        XCTAssertEqual(registry.blocks(for: text, scope: b)?.first?.block,
                       .widget("{\"title\":\"Активность\"}"))
        // Без области — ничего: разметка хода не утекает ни в роли, ни в историю.
        XCTAssertNil(registry.blocks(for: text), "запись с областью видна запросу без области")
        XCTAssertNil(registry.block(startingWith: text), "запись с областью видна запросу без области")

        // Экран: каждый ход рисует свою разметку.
        guard let segmentsA = preparedForScreen(text, scope: a) else {
            return XCTFail("путь экрана не нашёл блоки своего хода A")
        }
        guard let segmentsB = preparedForScreen(text, scope: b) else {
            return XCTFail("путь экрана не нашёл блоки своего хода B")
        }
        guard case .document? = segmentsA.first else {
            return XCTFail("ход A потерял свой текстовый блок: \(segmentsA)")
        }
        guard case .widget? = segmentsB.first else {
            return XCTFail("ход B потерял свой виджет: \(segmentsB)")
        }
        XCTAssertEqual(visibleText(segmentsA), text, "ход A показал не свой текст")
    }

    func testSameSessionTwoTurnsDoNotSwapBlocks() {
        let text = "Две карточки по одной задаче, текст совпал."
        let first = scope("scope-test-one-session", Date(timeIntervalSince1970: 1_764_000_100))
        let second = scope("scope-test-one-session", Date(timeIntervalSince1970: 1_764_000_900))
        XCTAssertNotEqual(first, second, "два хода одной сессии должны иметь разные области")

        registry.register(widgetBlocks(text), for: text, scope: first)
        registry.register(proseBlocks(text), for: text, scope: second)

        guard case .widget? = preparedForScreen(text, scope: first)?.first else {
            return XCTFail("первый ход потерял свой виджет")
        }
        guard case .document? = preparedForScreen(text, scope: second)?.first else {
            return XCTFail("второй ход получил чужой виджет")
        }
    }

    // MARK: — пересекающийся текст

    func testOverlappingTextTakesBlocksOfOwnTurn() {
        let short = "Сводка по проекту готова."
        let long = short + " Ещё два пункта в карточке."
        let a = scope("scope-test-overlap-a", turnStart)
        let b = scope("scope-test-overlap-b", turnStart)

        // Куски пересекаются: `short` — начало `long`, а поиск идёт по началу.
        registry.register(widgetBlocks(short), for: short, scope: a)
        registry.register(proseBlocks(long), for: long, scope: b)

        let shown = "Сводка по проекту"
        guard case .widget? = preparedForScreen(shown, scope: a)?.first else {
            return XCTFail("ход A взял разметку соседа с пересекающимся текстом")
        }
        guard case .document? = preparedForScreen(shown, scope: b)?.first else {
            return XCTFail("ход B потерял свой текстовый кусок")
        }
        // Без области пересекающийся текст не подхватывается вслепую.
        XCTAssertNil(preparedForScreen(shown, scope: nil))
    }

    // MARK: — чаты ролей и история: без области, как раньше

    func testUnscopedLookupsStayTextOnly() {
        let text = "Итог по роли: всё в порядке."
        let scoped = scope("scope-test-role", turnStart)

        registry.register(widgetBlocks(text), for: text, scope: scoped)
        XCTAssertNil(registry.blocks(for: text), "запрос без области увидел разметку хода сессии")

        registry.register(proseBlocks(text), for: text)
        XCTAssertEqual(registry.blocks(for: text)?.first?.source, text,
                       "чат роли потерял свою разметку без области")
        XCTAssertEqual(registry.block(startingWith: "Итог по роли")?.source, text,
                       "пейсер роли не нашёл блок без области")
        // Разметка хода сессии при этом не подменилась общей.
        XCTAssertEqual(registry.blocks(for: text, scope: scoped)?.first?.block,
                       .widget("{\"title\":\"Активность\"}"))
    }
}
