import XCTest

/// Идущий ответ сессии печатается кусками блоков сервера: `RoleLiveTextPacer`
/// раскладывает реплику по `ChatLiveBlock.source` и отдаёт экрану каждый кусок
/// отдельным пунктом, проявляя его по словам. Экран сессии обязан рисовать
/// такой кусок той же подготовленной разметкой, что и комната роли
/// (`ChatRichContent.liveSegments(shown:)`): поиск по точному тексту реплики
/// не находил ничего, и `RoleReplyMarkdown` показывал «Не удалось получить
/// подготовленное содержимое» вместо ответа из нескольких блоков.
///
/// Тест держит это свойство с двух сторон: ответ из нескольких блоков и
/// постепенное появление текста. Проверка «покажет заглушку» повторяет условие
/// `RoleReplyMarkdown` (пустые куски при непустом тексте), а `preparedForScreen`
/// повторяет выражение `SessionLiveTurnView.itemView` (случай `.text`).
final class SessionLiveBlocksRenderTests: XCTestCase {
    private let prose = "Сейчас покажу сводку.\n\n"
    private let widgetSource = "```widget\n{\"type\":\"summary\",\"title\":\"Активность\"}\n```"
    private var replyText: String { prose + widgetSource }

    // MARK: — путь экрана

    /// Ровно то, что экран сессии передаёт в `RoleReplyMarkdown`
    /// (`SessionLiveTurnView.itemView`, случай `.text`).
    private func preparedForScreen(_ shown: String) -> [ChatRichSegment]? {
        SessionLiveReplyContent.prepared(shown: shown)
    }

    /// Условие заглушки в `RoleReplyMarkdown`: кусков нет, а текст есть.
    private func showsPlaceholder(_ shown: String) -> Bool {
        (preparedForScreen(shown) ?? []).isEmpty && !shown.isEmpty
    }

    private func visibleText(_ segments: [ChatRichSegment]?) -> String {
        (segments ?? []).map { segment in
            switch segment {
            case .document(let blocks, _): return blocks.map(\.plainText).joined()
            case .table: return ""
            case .widget, .structuredJSON, .structuredJSONStreaming: return ""
            case .html(let html): return html
            case .pending: return ""
            }
        }.joined()
    }

    // MARK: — разметка сервера и проявление

    private func liveBlocks(_ json: String) -> [ChatLiveBlock] {
        guard let data = json.data(using: .utf8),
              let blocks = try? JSONDecoder().decode([ChatLiveBlock].self, from: data) else {
            XCTFail("разметка сервера не разобралась")
            return []
        }
        return blocks
    }

    /// Ответ из двух блоков сервера: проза и виджет — как их присылает сервер.
    private func twoBlockReplyBlocks() -> [ChatLiveBlock] {
        let doc = "{\"type\":\"doc\",\"doc\":{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\","
            + "\"content\":[{\"type\":\"text\",\"text\":\"Сейчас покажу сводку.\"}]}]},"
            + "\"chars\":23,\"source\":\"Сейчас покажу сводку.\\n\\n\"}"
        let widget = "{\"type\":\"widget\",\"json\":\"{\\\"type\\\":\\\"summary\\\",\\\"title\\\":\\\"Активность\\\"}\","
            + "\"source\":\"```widget\\n{\\\"type\\\":\\\"summary\\\",\\\"title\\\":\\\"Активность\\\"}\\n```\"}"
        return liveBlocks("[\(doc),\(widget)]")
    }

    /// Ответ из одного блока: обычный текст без спец-фенсов.
    private func proseOnlyBlocks(_ text: String) -> [ChatLiveBlock] {
        let json = "{\"type\":\"doc\",\"doc\":{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\","
            + "\"content\":[{\"type\":\"text\",\"text\":\"\(text)\"}]}]},"
            + "\"chars\":\(text.count),\"source\":\"\(text)\"}"
        return liveBlocks("[\(json)]")
    }

    /// Проявляет реплику по шагам и отдаёт все кадры показа (что видит экран).
    private func revealedFrames(of text: String, blocks: [ChatLiveBlock]) -> [[String]] {
        ChatLiveBlockRegistry.shared.register(blocks, for: text)
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text(text)], isFinal: true)
        var frames: [[String]] = [texts(pacer.visibleItems)]
        var step = 0
        while step < 400, pacer.advance(elapsed: 0.2, now: Date(timeIntervalSince1970: Double(step))) {
            frames.append(texts(pacer.visibleItems))
            step += 1
        }
        pacer.flush()
        frames.append(texts(pacer.visibleItems))
        return frames
    }

    private func texts(_ items: [RoleChatLiveItem]) -> [String] {
        items.compactMap { item in
            if case .text(let text) = item { return text }
            return nil
        }
    }

    // MARK: — тесты

    /// Ответ из нескольких блоков: на каждом кадре показа экран получает
    /// подготовленную разметку куска, а не заглушку.
    @objc func testMultiBlockReplyShowsPreparedSegments() {
        let frames = revealedFrames(of: replyText, blocks: twoBlockReplyBlocks())
        XCTAssertGreaterThan(frames.last?.count ?? 0, 1, "ответ с виджетом обязан делиться на куски")

        for frame in frames {
            for shown in frame {
                XCTAssertNotNil(preparedForScreen(shown), "кусок без разметки: \(shown.debugDescription)")
                XCTAssertFalse(showsPlaceholder(shown),
                               "на месте ответа встанет «Не удалось получить подготовленное "
                               + "содержимое»: \(shown.debugDescription)")
            }
        }
    }

    /// Постепенное появление: текст растёт по кускам, и каждый промежуточный
    /// кадр тоже получает разметку — проза обрезается по проявленной доле.
    @objc func testProseGrowsThroughPreparedSegments() {
        let frames = revealedFrames(of: replyText, blocks: twoBlockReplyBlocks())
        let proseFrames = frames.compactMap { $0.first }.filter { !$0.contains("```widget") }
        XCTAssertGreaterThanOrEqual(proseFrames.count, 2, "проза должна проявляться по словам")

        var previous = ""
        for shown in proseFrames {
            let segments = preparedForScreen(shown)
            XCTAssertFalse(showsPlaceholder(shown), "промежуточный кадр без разметки: \(shown.debugDescription)")
            let visible = visibleText(segments)
            XCTAssertFalse(visible.isEmpty, "кадр «\(shown)» рисуется пустым")
            XCTAssertTrue(prose.hasPrefix(visible) || visible.isEmpty,
                          "показанный текст не начало прозы: \(visible.debugDescription)")
            XCTAssertTrue(visible.hasPrefix(previous), "текст не растёт монотонно: \(visible.debugDescription)")
            previous = visible
        }
        XCTAssertEqual(previous, "Сейчас покажу сводку.",
                       "проза обязана дорасти до конца своего блока")
    }

    /// Одноблоковый ответ — прежнее поведение: один кусок, разметка на месте.
    @objc func testSingleBlockReplyShowsPreparedSegments() {
        let text = "Готово. Сводка собрана, вопросов нет."
        let frames = revealedFrames(of: text, blocks: proseOnlyBlocks(text))
        XCTAssertEqual(frames.last?.count, 1)
        for frame in frames {
            for shown in frame {
                XCTAssertFalse(showsPlaceholder(shown), "кусок без разметки: \(shown.debugDescription)")
            }
        }
        XCTAssertEqual(visibleText(preparedForScreen(text)), text)
    }
}
