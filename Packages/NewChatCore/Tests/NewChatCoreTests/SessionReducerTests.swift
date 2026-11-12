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
