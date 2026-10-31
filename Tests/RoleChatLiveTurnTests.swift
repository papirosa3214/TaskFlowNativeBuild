import Foundation
import XCTest
@testable import TaskFlow

/// Живой ход роли в чате (LOCK-229) — формы как их шлёт сервер
/// (`server/src/runtime/chatLiveTurn.ts`: `chats:live`, `chat_messages.steps`).
final class RoleChatLiveTurnTests: XCTestCase {
    func testEndingSnapshotStopsThinkingAndRunningStepsImmediately() {
        let turn = RoleChatLiveTurn(chatID: "chat", userID: "role", name: "Role", startedAt: "2026-10-11T14:20:51Z",
            items: [.text("Ответ"), .thinking(RoleChatThinking(id: "thought", text: "мысль", isRunning: true)),
                    .step(RoleChatLiveStep(id: "step", tool: "read", detail: nil, status: .running))], thinking: "", triggerMessageID: "question")
        let ended = turn.ending()
        XCTAssertNil(ended.thinking)
        XCTAssertEqual(ended.triggerMessageID, "question")
        if case .thinking(let thought) = ended.items[1] { XCTAssertFalse(thought.isRunning); XCTAssertNotNil(thought.endedAt) }
        else { XCTFail("thinking was lost") }
        if case .step(let step) = ended.items[2] { XCTAssertEqual(step.status, .done); XCTAssertNotNil(step.endedAt) }
        else { XCTFail("step was lost") }
    }

    func testSQLiteTimestampMatchesLiveTimestamp() {
        let stored = RoleChatTime.date("2026-10-11 14:20:50")
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored, RoleChatTime.date("2026-10-11T14:20:50.000Z"))
    }

    func testFirstCompleteWordAppearsWithoutArtificialBuffer() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Готово ")])
        for _ in 0..<10 { pacer.advance(elapsed: 0.016) }
        XCTAssertFalse(pacer.visibleItems.isEmpty)
    }

    /// Сервер вправе убрать из снимка законченное пустое размышление
    /// (`chatLiveTurn.ts`, `snapshot()`), и индексы пунктов сдвигаются.
    /// Проявленные шаги при этом теряться не должны: иначе видимый список
    /// обрезается, живой пузырь схлопывается на полосу, а лента, привязанная
    /// к низу, прыгает вниз и тут же обратно (владелец 25.10.2026).
    func testRevealedActionsSurviveRemovalFromSnapshot() {
        var pacer = RoleLiveTextPacer()
        let thinking = RoleChatLiveItem.thinking(RoleChatThinking(id: "thinking-0", text: "мысль", isRunning: false))
        let step = RoleChatLiveItem.step(RoleChatLiveStep(id: "step-0", tool: "read", detail: nil, status: .done))
        let emptyThinking = RoleChatLiveItem.thinking(RoleChatThinking(id: "thinking-1", text: "", isRunning: false))
        let lastStep = RoleChatLiveItem.step(RoleChatLiveStep(id: "step-1", tool: "bash", detail: nil, status: .done))
        pacer.ingest([thinking, step, emptyThinking, lastStep])
        for _ in 0..<40 { pacer.advance(elapsed: 0.1) }
        XCTAssertEqual(pacer.visibleItems.count, 4, "все действия должны проявиться")

        // Снимок без законченного пустого размышления: индексы сдвинулись.
        // С 30.10.2026 (`4d13c630`) показанный живой ход не укорачивается:
        // снимок, потерявший показанное действие, не принимается вовсе.
        pacer.ingest([thinking, step, lastStep])
        XCTAssertEqual(pacer.visibleItems.count, 4, "показанный живой ход не укорачивается")
        XCTAssertEqual(pacer.visibleItems.last?.id, "step-1")
    }

    /// Текст узнаём по порядку среди текстовых пунктов: сервер убрал пункт
    /// перед текстом — текст не должен проявляться заново с нуля.
    func testRevealedTextSurvivesRemovalOfEarlierItem() {
        var pacer = RoleLiveTextPacer()
        let step = RoleChatLiveItem.step(RoleChatLiveStep(id: "step-0", tool: "read", detail: nil, status: .done))
        pacer.ingest([step, .text("Проверил первую часть")])
        for _ in 0..<60 { pacer.advance(elapsed: 0.05) }
        let revealed = pacer.visibleItems.compactMap { item -> String? in
            if case .text(let text) = item { return text }; return nil
        }.first
        XCTAssertNotNil(revealed)
        XCTAssertFalse(revealed?.isEmpty ?? true)

        pacer.ingest([.text("Проверил первую часть")])
        let after = pacer.visibleItems.compactMap { item -> String? in
            if case .text(let text) = item { return text }; return nil
        }.first
        XCTAssertEqual(after, revealed, "проявленный текст не должен начинаться заново")
    }

    /// Пока ход идёт, одиночное действие — полосой: иначе полоса то
    /// появляется, то исчезает, и высота живого пузыря меняется (владелец
    /// 25.10.2026).
    func testLiveSegmentGroupsSingleActionForLiveTurn() {
        let items: [RoleChatLiveItem] = [
            .thinking(RoleChatThinking(id: "thinking-0", text: "", isRunning: true)),
            .text("Ответ")
        ]
        let обычные = RoleLiveSegment.split(items, grouping: true)
        XCTAssertEqual(обычные.count, 2)
        if case .actions = обычные[0] { XCTFail("в истории одиночное действие остаётся строкой") }

        let сПолосой = RoleLiveSegment.split(items, grouping: true, groupsSingleAction: true)
        XCTAssertEqual(сПолосой.count, 2)
        if case .actions(let group) = сПолосой[0] { XCTAssertEqual(group.count, 1) }
        else { XCTFail("одиночное действие должно стать полосой") }
        if case .single = сПолосой[1] {} else { XCTFail("текст остаётся строкой") }
    }

    func testFinalAnswerDrainsSmoothlyWithinCompletionWindow() {
        var pacer = RoleLiveTextPacer()
        let text = String(repeating: "готовый ответ ", count: 1000)
        pacer.ingest([.text(text)])
        pacer.finish()
        // Остаток не выскакивает разом, но и не ждёт дольше отведённого срока.
        XCTAssertTrue(pacer.hasPendingText)
        let ticks = Int(drainBudget(pacer) / 0.016) + 4
        for _ in 0..<ticks { pacer.advance(elapsed: 0.016) }
        XCTAssertFalse(pacer.hasPendingText)
        XCTAssertEqual(pacer.visibleItems, [.text(text)])
    }

    /// С 17.10.2026 (`1f58d8d7`) срок досыпа считается по остатку символов,
    /// а не как однократные две секунды: `finish()` даёт бюджет
    /// `max(completionDrain, остаток / maxRate + tailWait)`.
    func testCompletedLongReplyDrainsWithinDeclaredBudget() {
        var pacer = RoleLiveTextPacer()
        let text = String(repeating: "длинный ответ ", count: 1000)
        pacer.ingest([.text(text)])
        pacer.advance(elapsed: 0.2)
        XCTAssertTrue(pacer.hasPendingText)
        pacer.finish()
        let ticks = Int(drainBudget(pacer) / 0.016) + 4
        for _ in 0..<ticks { pacer.advance(elapsed: 0.016) }
        XCTAssertFalse(pacer.hasPendingText)
        XCTAssertEqual(pacer.visibleItems, [.text(text)])
    }

    func testRepeatedCompletionDoesNotPostponeDeadline() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text(String(repeating: "слово ", count: 1000))])
        pacer.finish()
        // Срок досыпа — по остатку символов (17.10.2026, `1f58d8d7`).
        let ticks = Int(drainBudget(pacer) / 0.016) + 4
        for _ in 0..<ticks {
            pacer.finish()
            pacer.advance(elapsed: 0.016)
        }
        XCTAssertFalse(pacer.hasPendingText)
    }

    private func parse(_ json: String) -> RealtimeEvent? {
        RealtimeEvent.parse(Data(json.utf8))
    }

    /// Срок досыпа, который `finish()` даёт живому ходу: с 17.10.2026
    /// (`1f58d8d7`) он считается по остатку символов, а `completionDrain` —
    /// только пол этого срока.
    private func drainBudget(_ pacer: RoleLiveTextPacer) -> TimeInterval {
        max(RoleLiveTextPacer.completionDrain,
            Double(pacer.pendingCharacters) / RoleLiveTextPacer.maxRate
            + RoleLiveTextPacer.tailWait)
    }

    /// Прокрутить часы очереди, пока текст не выйдет весь.
    private func drain(_ pacer: inout RoleLiveTextPacer, step: TimeInterval = 0.016) {
        var guardTicks = 10_000
        while pacer.hasPendingText && guardTicks > 0 {
            pacer.advance(elapsed: step)
            guardTicks -= 1
        }
    }

    func testRichBlocksAppearImmediatelyWithoutProseBudget() {
        for language in ["html", "artifact", "widget", "tf-widget"] {
            let source = "```\(language)\n" + String(repeating: "content ", count: 1000) + "\n```"
            var pacer = RoleLiveTextPacer()
            pacer.ingest([.text(source)])
            XCTAssertEqual(pacer.visibleItems, [.text(source)])
            XCTAssertEqual(pacer.pendingCharacters, 0)
            XCTAssertFalse(pacer.hasPendingText)
        }
    }

    func testRichContentOvertakesQueuedProseAndActionsButDoesNotRevealTail() {
        let prefix = String(repeating: "Объяснение ", count: 100) + "\n"
        let html = "```html\n<h1>Готово</h1>\n```\n"
        let widget = "```widget\n{\"type\":\"metric\"}\n```"
        let step = RoleChatLiveStep(id: "later", tool: "read", detail: nil, status: .done)
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text(prefix + html + "Обычный хвост"), .step(step), .text(widget)])
        XCTAssertEqual(pacer.visibleItems, [.text(html), .text(widget)])
        XCTAssertEqual(pacer.pendingCharacters, prefix.count + "Обычный хвост".count)
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text(prefix), .text(html), .text("Обычный хвост"), .step(step), .text(widget)])
    }

    func testIncompleteHTMLBecomesReadyOnIngestWhileProseRemainsQueued() {
        let prefix = String(repeating: "Слово ", count: 80) + "\n"
        let partial = "```html\n<h1>Привет"
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text(prefix + partial)])
        XCTAssertEqual(pacer.visibleItems, [.text(partial)])
        XCTAssertEqual(ChatRichContent.split(partial), [.pending(.html)])
        pacer.advance(elapsed: 1)
        let progress = pacer.visibleCharacters[0]
        let ready = partial + "</h1>\n```"
        pacer.ingest([.text(prefix + ready)])
        XCTAssertEqual(pacer.visibleCharacters[0], progress)
        XCTAssertTrue(pacer.visibleItems.contains(.text(ready)))
        XCTAssertEqual(ChatRichContent.split(ready), [.html("<h1>Привет</h1>")])
    }

    func testOrdinaryCodeStaysPacedAndUnicodeCRLFFencesRemainIntact() {
        let ordinary = "```swift\nlet value = 1\n```"
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text(ordinary)])
        XCTAssertTrue(pacer.visibleItems.isEmpty)
        let prefix = "Привет 👨‍👩‍👧‍👦\r\n"
        let html = "```HTML\r\n<h1>Привет 🌍</h1>\r\n```\r\n"
        pacer.ingest([.text(prefix + html + "После")])
        XCTAssertEqual(pacer.visibleItems, [.text(html)])
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text(prefix), .text(html), .text("После")])
    }

    func testPacerRevealsWholeWordsAndPreservesProgressAcrossSnapshots() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Привет, как дела")])
        pacer.advance(elapsed: RoleLiveTextPacer.initialBuffer)
        pacer.advance(elapsed: 0.4)
        guard case .text(let first)? = pacer.visibleItems.first else {
            return XCTFail("ожидали начало текста")
        }
        // Слово целиком, без обрывков: «Привет,» или «Привет, как».
        XCTAssertTrue(["Привет,", "Привет, как", "Привет, как дела"].contains(first), "показано: \(first)")
        pacer.ingest([.text("Привет, как дела? Всё хорошо.")])
        XCTAssertEqual(pacer.visibleItems, [.text(first)])
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text("Привет, как дела? Всё хорошо.")])
    }

    func testPacerWaitsForCutWordThenShowsIt() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Смотрю доск")])
        // Первое слово успевает выйти, а хвост «доск» может дописаться — ждём.
        pacer.advance(elapsed: RoleLiveTextPacer.initialBuffer)
        for _ in 0..<8 { pacer.advance(elapsed: 0.016) }
        XCTAssertEqual(pacer.visibleItems, [.text("Смотрю")])
        pacer.ingest([.text("Смотрю доску")])
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text("Смотрю доску")])
    }

    func testPacerSpeedsUpWithBacklog() {
        var slow = RoleLiveTextPacer()
        slow.ingest([.text(String(repeating: "слово ", count: 5))])
        var fast = RoleLiveTextPacer()
        fast.ingest([.text(String(repeating: "слово ", count: 300))])
        for _ in 0..<100 {
            slow.advance(elapsed: 0.016)
            fast.advance(elapsed: 0.016)
        }
        XCTAssertGreaterThan(fast.rate, slow.rate)
        XCTAssertLessThanOrEqual(fast.rate, RoleLiveTextPacer.maxRate)
    }

    func testPacerShowsStepsAfterPreviousTextAndResetsChangedText() {
        let step = RoleChatLiveStep(id: "s", tool: "read", detail: nil, status: .running)
        let thinking = RoleChatThinking(id: "t", text: "Думаю", isRunning: true)
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Проверяю файл"), .step(step), .thinking(thinking), .text("Готово")])
        pacer.advance(elapsed: 0.05)
        XCTAssertFalse(pacer.visibleItems.contains(.step(step)), "шаг не обгоняет текст перед ним")
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, [.text("Проверяю файл"), .step(step), .thinking(thinking), .text("Готово")])
        // Изменившийся текст начинается заново: снимок с теми же действиями и
        // новым текстом принимается, и показанный «Готово» уходит. Снимок,
        // потерявший показанные действия, не принимается вовсе
        // (RoleLiveTurnGrowth, 30.10.2026).
        pacer.ingest([.text("Проверяю файл"), .step(step), .thinking(thinking), .text("Новый ответ")])
        XCTAssertFalse(pacer.visibleItems.contains(.text("Готово")),
                       "изменившийся текст должен начинаться заново")
        XCTAssertEqual(pacer.visibleItems.count, 3)
    }

    func testActionOnlyBurstIsQueuedAndPreservesStatusUpdates() {
        let steps = (0..<4).map { RoleChatLiveStep(id: "s\($0)", tool: "read", detail: nil, status: .running) }
        var pacer = RoleLiveTextPacer()
        pacer.ingest(steps.map { .step($0) })
        XCTAssertTrue(pacer.hasPendingText)
        XCTAssertTrue(pacer.visibleItems.isEmpty)
        pacer.advance(elapsed: 0.016)
        XCTAssertEqual(pacer.visibleItems.count, 1)
        pacer.advance(elapsed: 0.016)
        XCTAssertEqual(pacer.visibleItems.count, 1)
        let updated = RoleChatLiveStep(id: "s0", tool: "read", detail: nil, status: .done)
        pacer.ingest([.step(updated)] + steps.dropFirst().map { .step($0) })
        XCTAssertEqual(pacer.visibleItems, [.step(updated)])
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems.count, 4)
        XCTAssertFalse(pacer.hasPendingText)
    }

    func testSnapshotSeedDoesNotFadeOrReplayExistingItems() {
        var pacer = RoleLiveTextPacer()
        let step = RoleChatLiveStep(id: "s", tool: "read", detail: nil, status: .done)
        let snapshot: [RoleChatLiveItem] = [.text("Уже прочитанный текст"), .step(step)]
        pacer.ingest(snapshot)
        pacer.flush()
        XCTAssertEqual(pacer.visibleItems, snapshot)
        XCTAssertFalse(pacer.hasPendingText)
        XCTAssertEqual(pacer.lastRevealAt, .distantPast)
        pacer.ingest(snapshot + [.text("Новый текст")])
        XCTAssertEqual(pacer.visibleItems, snapshot)
        drain(&pacer)
        XCTAssertEqual(pacer.visibleItems, snapshot + [.text("Новый текст")])
    }

    @MainActor
    func testDriverStopsAnimatingAfterQueueAndFadeDrain() {
        let driver = RoleLivePacerDriver()
        XCTAssertFalse(driver.isAnimating(now: .now))
        driver.pacer.ingest([.text("Ответ")])
        XCTAssertTrue(driver.isAnimating(now: .now))
        driver.pacer.advance(elapsed: RoleLiveTextPacer.initialBuffer)
        driver.pacer.advance(elapsed: 1)
        XCTAssertFalse(driver.pacer.hasPendingText)
        XCTAssertFalse(driver.isAnimating(now: .now.addingTimeInterval(1)))
    }

    func testLongReplyCatchesUpWithoutArtificialReadingDelay() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text(String(repeating: "слово ", count: 300))])
        for _ in 0..<60 { pacer.advance(elapsed: 1.0 / 60) }
        guard case .text(let shown)? = pacer.visibleItems.first else { return XCTFail("Нет текста") }
        // Ровный разгон: за секунду текст заметно продвинулся, но без рывка.
        XCTAssertGreaterThan(shown.count, 150)
        XCTAssertLessThanOrEqual(pacer.rate, RoleLiveTextPacer.maxRate)
        pacer.finish()
        // Срок досыпа — по остатку символов (17.10.2026, `1f58d8d7`).
        let ticks = Int(drainBudget(pacer) / 0.016) + 4
        for _ in 0..<ticks { pacer.advance(elapsed: 0.016) }
        XCTAssertFalse(pacer.hasPendingText)
    }

    func testExistingTailDoesNotDimWhenNewWordArrives() {
        let start = Date(timeIntervalSince1970: 100)
        let arrival = start.addingTimeInterval(0.6)
        let history = RoleTextRevealHistory()
        history.record(count: 2, now: start, rate: 18, animated: true, forward: false)
        let before = history.opacity(at: 1, now: arrival)
        history.record(count: 5, now: arrival, rate: 36, animated: true, forward: false)
        XCTAssertGreaterThanOrEqual(history.opacity(at: 1, now: arrival), before)
        XCTAssertEqual(history.opacity(at: 4, now: arrival), 0, accuracy: 0.001)
        history.record(count: 12, now: arrival.addingTimeInterval(0.5), rate: 18, animated: true, forward: false)
        XCTAssertEqual(history.opacity(at: 1, now: arrival.addingTimeInterval(0.5)), 1, accuracy: 0.001)
    }

    func testRevealFadeGrowsWithDistanceAndTime() {
        let now = Date(timeIntervalSince1970: 100)
        let history = RoleTextRevealHistory()
        history.record(count: 21, now: now, rate: 100, animated: true, forward: false)
        XCTAssertEqual(history.opacity(at: 20, now: now), 0, accuracy: 0.001)
        XCTAssertGreaterThan(history.opacity(at: 0, now: now), history.opacity(at: 15, now: now))
        XCTAssertEqual(history.opacity(at: 20, now: now.addingTimeInterval(1)), 1, accuracy: 0.001)
    }

    func testSettledGlyphsRemainVisibleAfterPauseAndSnapshot() {
        let now = Date(timeIntervalSince1970: 100)
        let history = RoleTextRevealHistory()
        history.record(count: 10, now: now, rate: 18, animated: false, forward: false)
        history.record(count: 14, now: now.addingTimeInterval(2), rate: 36, animated: true, forward: false)
        for index in 0..<10 { XCTAssertEqual(history.opacity(at: index, now: now.addingTimeInterval(2)), 1) }
        // Shrinking/reflow keeps the existing prefix's original timestamps.
        history.record(count: 9, now: now.addingTimeInterval(2), rate: 36, animated: true, forward: false)
        XCTAssertEqual(history.opacity(at: 8, now: now.addingTimeInterval(2)), 1)
    }

    func testLiveEventCarriesThinkingItem() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"c","user_id":"r",
         "turn":{"chat_id":"c","user_id":"r","name":"QA","thinking":"Смотрю.",
                 "items":[{"kind":"thinking","id":"thinking-0","tool":"thinking",
                           "text":"Смотрю. Потом сравню","status":"running",
                           "started_at":"2026-09-30T09:00:00.000Z"}]}}
        """#)
        guard case .roleChatLive(_, _, let turn, _) = event, let turn else {
            return XCTFail("ожидали снимок")
        }
        XCTAssertEqual(turn.runningThinking?.text, "Смотрю. Потом сравню")
        XCTAssertEqual(turn.items.filter(\.isStep).count, 0)
    }

    func testSavedThinkingHasDuration() throws {
        let json = #"""
        {"duration_ms":15000,"items":[
          {"kind":"thinking","id":"thinking-0","tool":"thinking","text":"План.","status":"done",
           "started_at":"2026-09-30T09:00:00.000Z","ended_at":"2026-09-30T09:00:12.400Z"}]}
        """#
        let steps = try JSONDecoder().decode(RoleChatSteps.self, from: Data(json.utf8))
        XCTAssertTrue(steps.hasDetails)
        XCTAssertEqual(steps.stepCount, 0)
        guard case .thinking(let thinking)? = steps.items.first else { return XCTFail("ожидали размышление") }
        XCTAssertFalse(thinking.isRunning)
        XCTAssertEqual(thinking.durationSeconds, 12)
    }

    func testLiveEventCarriesTextAndSteps() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"chat-secretary","user_id":"u-secretary",
         "turn":{"chat_id":"chat-secretary","user_id":"u-secretary","name":"Помощник владельца",
                 "started_at":"2026-09-27T09:00:00.000Z",
                 "items":[{"kind":"text","text":"Смотрю."},
                          {"kind":"step","id":"c1","tool":"read","detail":"~/a.txt",
                           "status":"running","started_at":"2026-09-27T09:00:01.000Z"}]}}
        """#)
        guard case .roleChatLive(let chatID, let userID, let turn, _) = event, let turn else {
            return XCTFail("ожидали roleChatLive со снимком, пришло \(String(describing: event))")
        }
        XCTAssertEqual(chatID, "chat-secretary")
        XCTAssertEqual(userID, "u-secretary")
        XCTAssertEqual(turn.name, "Помощник владельца")
        XCTAssertNotNil(turn.startDate)
        XCTAssertEqual(turn.items, [
            .text("Смотрю."),
            .step(RoleChatLiveStep(id: "c1", tool: "read", detail: "~/a.txt", status: .running,
                                   startedAt: "2026-09-27T09:00:01.000Z")),
        ])
    }

    func testLiveEventWithNullTurnMeansFinished() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"chat-1","user_id":"role_qa","turn":null}
        """#)
        guard case .roleChatLive(_, let userID, let turn, _) = event else {
            return XCTFail("ожидали roleChatLive")
        }
        XCTAssertEqual(userID, "role_qa")
        XCTAssertNil(turn)
    }

    func testUnknownStepStatusDoesNotBreakSnapshot() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"c","user_id":"r",
         "turn":{"chat_id":"c","user_id":"r","name":"QA","items":[
           {"kind":"step","id":"s","tool":"mcp_x","status":"queued"}]}}
        """#)
        guard case .roleChatLive(_, _, let turn, _) = event, let turn else {
            return XCTFail("ожидали снимок")
        }
        XCTAssertEqual(turn.items, [.step(RoleChatLiveStep(id: "s", tool: "mcp_x", detail: nil, status: .running))])
    }

    func testMessageDecodesSavedSteps() throws {
        let json = #"""
        {"id":"m1","chat_id":"c","from_user_id":"role_qa","text":"Готово","is_session_marker":false,
         "steps":{"duration_ms":42500,"items":[
           {"kind":"text","text":"Проверяю"},
           {"kind":"step","id":"a","tool":"bash","detail":"npm test","status":"done"},
           {"kind":"step","id":"b","tool":"read","detail":null,"status":"error"}]}}
        """#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        let steps = try XCTUnwrap(message.steps)
        XCTAssertEqual(steps.durationMs, 42500)
        XCTAssertEqual(steps.stepCount, 2)
        XCTAssertEqual(steps.items.first, .text("Проверяю"))
    }

    func testMessageWithoutStepsStillDecodes() throws {
        let json = #"""
        {"id":"m2","chat_id":"c","from_user_id":"u1","text":"привет","is_session_marker":false,"steps":null}
        """#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.steps)
    }

    func testStepsAndDurationWording() {
        XCTAssertEqual(RoleLiveFormat.steps(1), "1 шаг")
        XCTAssertEqual(RoleLiveFormat.steps(3), "3 шага")
        XCTAssertEqual(RoleLiveFormat.steps(7), "7 шагов")
        XCTAssertEqual(RoleLiveFormat.steps(12), "12 шагов")
        XCTAssertEqual(RoleLiveFormat.steps(21), "21 шаг")
        XCTAssertEqual(RoleLiveFormat.duration(seconds: 42), "42 с")
        XCTAssertEqual(RoleLiveFormat.duration(seconds: 185), "3 мин 5 с")
        XCTAssertEqual(RoleLiveFormat.duration(seconds: 720), "12 мин")
        XCTAssertEqual(RoleLiveStepKind.label(forTool: "bash"), "Команда")
        XCTAssertEqual(RoleLiveStepKind.label(forTool: "taskflow_taskflow_agents"), "Трекер")
        XCTAssertEqual(RoleLiveStepKind.label(forTool: "web_search"), "Действие")
    }
}
