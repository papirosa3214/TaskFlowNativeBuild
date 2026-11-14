import XCTest
@testable import NewChatCore

final class SessionReducerTests: XCTestCase {
    func testSnapshotDecodesTreeAndParentRelationship() throws {
        let json = #"""
        {
          "id":"fork-1","cwd":"/project","sessionFile":"/sessions/fork.jsonl",
          "parentSession":"/sessions/root.jsonl","relation":"fork","leafId":"entry-2",
          "isStreaming":false,"isIdle":true,
          "entries":[{"type":"message","id":"entry-1","parentId":null}],
          "tree":[{"entry":{"type":"message","id":"entry-1","parentId":null},"children":[]}]
        }
        """#

        let snapshot = try XCTUnwrap(SessionSnapshot(json: try JSONValue.parse(json)))

        XCTAssertEqual(snapshot.id, "fork-1")
        XCTAssertEqual(snapshot.parentSession, "/sessions/root.jsonl")
        XCTAssertEqual(snapshot.relation, .fork)
        XCTAssertEqual(snapshot.leafId, "entry-2")
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.tree.count, 1)
    }

    func testDeltaIsReplacedByAuthoritativeMessageEnd() throws {
        var state = SessionState(snapshot: .fixture(id: "root"))
        let delta = try event(#"{"cursor":"c1","sessionId":"root","type":"assistant_text_delta","timestamp":"t","payload":{"delta":"Hel","contentIndex":0}}"#)
        let end = try event(#"{"cursor":"c2","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}}"#)

        SessionReducer.apply(delta, to: &state)
        XCTAssertEqual(state.transientAssistantText, "Hel")
        SessionReducer.apply(end, to: &state)

        XCTAssertEqual(state.transientAssistantText, "")
        XCTAssertEqual(state.messages, [SessionRenderedMessage(role: "assistant", text: "Hello")])
        XCTAssertEqual(state.lastCursor, "c2")
    }

    func testDuplicateCursorIsIgnored() throws {
        var state = SessionState(snapshot: .fixture(id: "root"))
        let delta = try event(#"{"cursor":"same","sessionId":"root","type":"assistant_text_delta","timestamp":"t","payload":{"delta":"A","contentIndex":0}}"#)

        SessionReducer.apply(delta, to: &state)
        SessionReducer.apply(delta, to: &state)

        XCTAssertEqual(state.transientAssistantText, "A")
        XCTAssertEqual(state.seenCursors, ["same"])
    }

    func testUnknownEventPayloadIsPreserved() throws {
        var state = SessionState(snapshot: .fixture(id: "root"))
        let unknown = try event(#"{"cursor":"u1","sessionId":"root","type":"pi_unknown","timestamp":"t","payload":{"piType":"future","event":{"value":3}}}"#)

        SessionReducer.apply(unknown, to: &state)

        XCTAssertEqual(state.unknownEvents, [unknown])
        XCTAssertEqual(unknown.payload["event"], .object(["value": .number(3)]))
    }

    func testChildSessionEventsDoNotOverwriteParentDraft() throws {
        var state = SessionState(snapshot: .fixture(id: "parent"))
        state.transientAssistantText = "parent"
        let child = try event(#"{"cursor":"child-1","sessionId":"child","type":"agent_settled","timestamp":"t","payload":{"aborted":false}}"#)

        SessionReducer.apply(child, to: &state)

        XCTAssertEqual(state.transientAssistantText, "parent")
        XCTAssertEqual(state.childActivity["child"], .settled)
    }

    func testReconnectResetConvergesFromSnapshotThenEvents() throws {
        var state = SessionState(snapshot: .fixture(id: "stale"))
        state.transientAssistantText = "stale draft"
        let snapshot = SessionSnapshot.fixture(id: "root")
        let settled = try event(#"{"cursor":"r2","sessionId":"root","type":"agent_settled","timestamp":"t","payload":{"aborted":false}}"#)
        let reconnect = SessionReconnectPayload(resetRequired: true, events: [settled], snapshot: snapshot)

        SessionReducer.apply(reconnect, to: &state)

        XCTAssertEqual(state.snapshot?.id, "root")
        XCTAssertEqual(state.transientAssistantText, "")
        XCTAssertEqual(state.lastCursor, "r2")
        XCTAssertFalse(state.needsSnapshotReset)
    }

    func testReconnectResetDoesNotReplayMessageAlreadyContainedInSnapshot() throws {
        let entry: JSONValue = .object([
            "type": .string("message"),
            "id": .string("entry-1"),
            "message": .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("text"), "text": .string("Ready")])]),
            ]),
        ])
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: "entry-1",
            isStreaming: false, isIdle: true, entries: [entry], tree: []
        )
        let messageEnd = try event(#"{"cursor":"r3","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Ready"}]}}}"#)
        var state = SessionState(snapshot: .fixture(id: "stale"))

        SessionReducer.apply(
            SessionReconnectPayload(resetRequired: true, events: [messageEnd], snapshot: snapshot),
            to: &state
        )

        XCTAssertEqual(state.snapshot?.entries, [entry])
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.lastCursor, "r3")
    }

    /// Сервер `c90c2c18`: при сбросе приходит снимок со своей точкой, а
    /// `events` — только окно новее неё. Снимок — основа, окно проигрывается
    /// по порядку; запись не новее точки уже в `entries` и не повторяется.
    func testReconnectResetReplaysOnlyEventsAfterSnapshotPoint() throws {
        let entry: JSONValue = .object([
            "type": .string("message"),
            "id": .string("entry-1"),
            "message": .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("text"), "text": .string("Ready")])]),
            ]),
        ])
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: "entry-1",
            isStreaming: true, isIdle: false, entries: [entry], tree: [],
            eventCursor: "e:10", eventCursorEpoch: "e", eventCursorSeq: 10
        )
        // e:9 — уже в снимке (сервер старой версии мог прислать и его);
        // e:11 и e:12 — окно незавершённого ответа после точки.
        let stale = try event(#"{"cursor":"e:9","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Ready"}]}}}"#)
        let windowDelta = try event(#"{"cursor":"e:11","sessionId":"root","type":"assistant_text_delta","timestamp":"t","payload":{"delta":"Tail"}}"#)
        let windowEnd = try event(#"{"cursor":"e:12","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Tail"}]}}}"#)
        var state = SessionState(snapshot: .fixture(id: "stale"))
        state.lastCursor = "e:1"

        let payload = SessionReconnectPayload(
            resetRequired: true, events: [stale, windowDelta, windowEnd], snapshot: snapshot
        )
        SessionReducer.apply(payload, to: &state)

        XCTAssertEqual(state.snapshot?.id, "root")
        XCTAssertEqual(state.snapshot?.entries, [entry], "снимок — основа, его записи не переписываются")
        XCTAssertEqual(
            SessionReconnectReplay.events(payload, sessionID: "root").map(\.cursor), ["e:11", "e:12"],
            "в живой ход — ровно окно после точки, по порядку"
        )
        XCTAssertEqual(state.transientAssistantText, "")
        XCTAssertEqual(state.messages, [SessionRenderedMessage(role: "assistant", text: "Tail")],
                       "событие не новее точки не повторяет запись снимка")
        XCTAssertEqual(state.lastCursor, "e:12", "догон продолжается с последнего проигранного")
        XCTAssertFalse(state.needsSnapshotReset)
    }

    /// `eventsLost`: голову окна вытеснило, но события новее точки снимка
    /// известны поимённо — их проигрывать можно и нужно: их в `entries`
    /// снимка быть не может (контракт по точке). Курсор за вытесненную
    /// середину не откатывается: остаётся на последнем проигранном событии
    /// (ревью владельца 14.11.2026 — вечная дыра на точке снимка давала сброс
    /// на каждом переподключении).
    func testReconnectResetEventsLostStillReplaysEventsNewerThanPoint() throws {
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: true, isIdle: false, entries: [], tree: [],
            eventCursor: "e:500", eventCursorEpoch: "e", eventCursorSeq: 500
        )
        let tail = try event(#"{"cursor":"e:512","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Tail"}]}}}"#)
        let payload = SessionReconnectPayload(
            resetRequired: true, events: [tail], snapshot: snapshot, eventsLost: true
        )
        var state = SessionState(snapshot: .fixture(id: "stale"))

        XCTAssertEqual(SessionReconnectReplay.events(payload, sessionID: "root").map(\.cursor), ["e:512"],
                       "событие новее точки в снимке не лежит — его проигрываем")
        SessionReducer.apply(payload, to: &state)

        XCTAssertEqual(state.snapshot?.id, "root")
        XCTAssertEqual(state.messages, [SessionRenderedMessage(role: "assistant", text: "Tail")])
        XCTAssertEqual(state.lastCursor, "e:512",
                       "за вытесненную дыру 501…511 курсор не откатывается")
        XCTAssertFalse(state.needsSnapshotReset)
    }

    /// `eventsLost` и событие, пришедшее по сокету, пока ответ был в пути:
    /// оно новее точки снимка и в ответ не попало. Раньше общий запрет на
    /// `eventsLost` выбрасывал и его, а курсор уходил вперёд — `agent_settled`
    /// и `message_end` терялись навсегда (ревью владельца 14.11.2026).
    func testReconnectResetEventsLostKeepsCarriedSocketEvents() throws {
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: true, isIdle: false, entries: [], tree: [],
            eventCursor: "e:500", eventCursorEpoch: "e", eventCursorSeq: 500
        )
        let carriedEnd = try event(#"{"cursor":"e:512","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Tail"}]}}}"#)
        let carriedSettled = try event(#"{"cursor":"e:513","sessionId":"root","type":"agent_settled","timestamp":"t","payload":{}}"#)
        let payload = SessionReconnectPayload(
            resetRequired: true, events: [], snapshot: snapshot, eventsLost: true
        )
        var state = SessionState(snapshot: .fixture(id: "stale"))
        state.lastCursor = "e:513"

        let replay = SessionReconnectReplay.events(
            payload, sessionID: "root", carried: [carriedSettled, carriedEnd]
        )
        XCTAssertEqual(replay.map(\.cursor), ["e:512", "e:513"])

        SessionReducer.apply(payload, replay: replay, to: &state)

        XCTAssertEqual(state.messages, [SessionRenderedMessage(role: "assistant", text: "Tail")],
                       "окончание хода из очереди не теряется")
        XCTAssertEqual(state.snapshot?.isStreaming, false)
        XCTAssertEqual(state.snapshot?.isIdle, true)
        XCTAssertEqual(state.lastCursor, "e:513",
                       "очередь знает окончание окна: курсор не остаётся на вытесненной точке")
    }

    /// Другая эпоха ленты — другая лента: её события снимку не принадлежат и
    /// не проигрываются, курсор остаётся на точке снимка.
    func testReconnectResetSkipsEventsFromAnotherEpoch() throws {
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: false, isIdle: true, entries: [], tree: [],
            eventCursor: "e:10", eventCursorEpoch: "e", eventCursorSeq: 10
        )
        let foreign = try event(#"{"cursor":"f:12","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Old epoch"}]}}}"#)
        let payload = SessionReconnectPayload(resetRequired: true, events: [foreign], snapshot: snapshot)
        var state = SessionState(snapshot: .fixture(id: "stale"))

        SessionReducer.apply(payload, to: &state)

        XCTAssertEqual(SessionReconnectReplay.events(payload, sessionID: "root"), [])
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.lastCursor, "e:10")
    }

    /// Событие, пришедшее по сокету, пока ответ на сброс был в пути, сервер в
    /// ответ уже не положил. Оно не новее точки снимка быть не может (точка
    /// ниже), поэтому проигрывается вместе с окном, в порядке ленты и без
    /// повторов (ревью `7c7b5da0`, владелец 14.11.2026).
    func testReconnectResetAppliesEventArrivedWhileResponseInFlight() throws {
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: true, isIdle: false, entries: [], tree: [],
            eventCursor: "e:10", eventCursorEpoch: "e", eventCursorSeq: 10
        )
        let windowDelta = try event(#"{"cursor":"e:11","sessionId":"root","type":"assistant_text_delta","timestamp":"t","payload":{"delta":"Tail"}}"#)
        let inFlightEnd = try event(#"{"cursor":"e:12","sessionId":"root","type":"message_end","timestamp":"t","payload":{"message":{"role":"assistant","content":[{"type":"text","text":"Tail"}]}}}"#)
        var state = SessionState(snapshot: .fixture(id: "root"))
        state.lastCursor = "e:10"

        let payload = SessionReconnectPayload(resetRequired: true, events: [windowDelta], snapshot: snapshot)
        // В очереди пришедшего сокетом — тот же e:11 (повтор) и e:12.
        let replay = SessionReconnectReplay.events(
            payload, sessionID: "root", carried: [inFlightEnd, windowDelta]
        )

        XCTAssertEqual(replay.map(\.cursor), ["e:11", "e:12"], "порядок ленты, без повторов")

        SessionReducer.apply(payload, replay: replay, to: &state)

        XCTAssertEqual(state.transientAssistantText, "", "e:12 закрывает ответ")
        XCTAssertEqual(state.messages, [SessionRenderedMessage(role: "assistant", text: "Tail")],
                       "событие, пришедшее во время ответа, не теряется")
        XCTAssertEqual(state.lastCursor, "e:12", "догон продолжается с последнего проигранного")
    }

    /// `eventsLost`: точка снимка старше того, что клиент уже принял до
    /// сброса, но эти данные сервер вытеснил физически — повтором их не
    /// вернуть. Курсор поэтому не откатывается к вытесненной точке: иначе
    /// каждый обрыв просил бы её и снова получал сброс. Дыру это не
    /// «восстанавливает» — потерянное остаётся потерянным (ревью владельца
    /// 14.11.2026).
    func testReconnectResetEventsLostDoesNotReturnCursorToEvictedPoint() throws {
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: true, isIdle: false, entries: [], tree: [],
            eventCursor: "e:500", eventCursorEpoch: "e", eventCursorSeq: 500
        )
        let payload = SessionReconnectPayload(
            resetRequired: true, events: [], snapshot: snapshot, eventsLost: true
        )
        var state = SessionState(snapshot: .fixture(id: "stale"))
        state.lastCursor = "e:520"

        SessionReducer.apply(payload, to: &state)

        XCTAssertEqual(state.snapshot?.id, "root")
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.lastCursor, "e:520",
                       "курсор остаётся на последнем известном событии, не на вытесненной точке")

        // Прежняя эпоха — другая лента: её курсор к снимку не относится.
        state.lastCursor = "f:520"
        SessionReducer.apply(payload, to: &state)
        XCTAssertEqual(state.lastCursor, "e:500")
    }

    /// Дыра, которую закроет повтор (усечённая очередь), — курсор остаётся
    /// на точке снимка: следующий догон спросит окно заново.
    func testReconnectResetRecoverableWindowKeepsPointCursor() throws {
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: true, isIdle: false, entries: [], tree: [],
            eventCursor: "e:500", eventCursorEpoch: "e", eventCursorSeq: 500
        )
        let tail = try event(#"{"cursor":"e:512","sessionId":"root","type":"agent_settled","timestamp":"t","payload":{}}"#)
        let payload = SessionReconnectPayload(
            resetRequired: true, events: [tail], snapshot: snapshot
        )
        var state = SessionState(snapshot: .fixture(id: "stale"))
        state.lastCursor = "e:520"

        SessionReducer.apply(
            payload, replay: SessionReconnectReplay.events(payload, sessionID: "root"),
            replayComplete: false, to: &state
        )

        XCTAssertEqual(state.lastCursor, "e:500",
                       "неполное окно не перепрыгиваем: следующий догон спросит с точки")
    }

    /// Сохранённый живой ход уже получил `carried` в `receive`: в него идут
    /// только события ответа, иначе шаги и куски текста задваиваются.
    /// Пересозданное состояние получает окно целиком.
    func testLiveEventsKeptTurnExcludesCarriedAlreadyApplied() throws {
        let snapshot = SessionSnapshot(
            id: "root", cwd: "/project", sessionFile: "/sessions/root.jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: true, isIdle: false, entries: [], tree: [],
            eventCursor: "e:500", eventCursorEpoch: "e", eventCursorSeq: 500
        )
        let fromResponse = try event(#"{"cursor":"e:512","sessionId":"root","type":"tool_start","timestamp":"t","payload":{}}"#)
        let carried = try event(#"{"cursor":"e:513","sessionId":"root","type":"tool_start","timestamp":"t","payload":{}}"#)
        let payload = SessionReconnectPayload(
            resetRequired: true, events: [fromResponse], snapshot: snapshot, eventsLost: true
        )

        XCTAssertEqual(
            SessionReconnectReplay.liveEvents(
                payload, sessionID: "root", carried: [carried], keepingCurrent: true
            ).map(\.cursor),
            ["e:512"],
            "сохранённому ходу не повторяем то, что уже применил receive"
        )
        XCTAssertEqual(
            SessionReconnectReplay.liveEvents(
                payload, sessionID: "root", carried: [carried], keepingCurrent: false
            ).map(\.cursor),
            ["e:512", "e:513"],
            "пересозданный ход получает окно целиком"
        )
    }

    /// Пока известна дыра, догон просит от неё, хотя живые события уже увели
    /// `lastCursor` вперёд. Курсор из другой эпохи к текущей ленте не относится.
    func testResumeCursorKeepsKnownGap() {
        XCTAssertEqual(
            SessionReconnectReplay.resumeCursor(lastCursor: "e:530", recovering: "e:500"),
            "e:500"
        )
        XCTAssertEqual(
            SessionReconnectReplay.resumeCursor(lastCursor: "e:530", recovering: nil),
            "e:530"
        )
        XCTAssertEqual(
            SessionReconnectReplay.resumeCursor(lastCursor: "e:530", recovering: "f:500"),
            "e:530"
        )
        XCTAssertEqual(SessionReconnectReplay.resumeCursor(lastCursor: nil, recovering: "e:500"), "e:500")
    }

    func testMissingReconnectSnapshotRequestsReset() {
        var state = SessionState(snapshot: .fixture(id: "root"))

        SessionReducer.apply(SessionReconnectPayload(resetRequired: true, events: [], snapshot: nil), to: &state)

        XCTAssertTrue(state.needsSnapshotReset)
    }

    private func event(_ json: String) throws -> SessionEventEnvelope {
        try XCTUnwrap(SessionEventEnvelope(json: try JSONValue.parse(json)))
    }
}

private extension SessionSnapshot {
    static func fixture(id: String) -> SessionSnapshot {
        SessionSnapshot(
            id: id, cwd: "/project", sessionFile: "/sessions/\(id).jsonl",
            parentSession: nil, name: nil, leafId: nil,
            isStreaming: false, isIdle: true, entries: [], tree: []
        )
    }
}
