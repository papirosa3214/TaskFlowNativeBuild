import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Приём живого хода роли дельтами (`chats:live:start/patch/end`,
/// карточка TaskFlow 7b73b9c9, Linear MAK-137): события применяются по порядку `seq`,
/// пропуск номера просит снимок, конец хода отдаёт номер готового сообщения.
final class RoleChatLiveDeltaTests: XCTestCase {
    private func event(_ json: String) -> RoleChatLiveDelta {
        try! JSONDecoder().decode(RoleChatLiveDelta.self, from: Data(json.utf8))
    }

    private func started() -> RoleChatLiveTurnState {
        let start = event(#"{"type":"chats:live:start","chat_id":"c1","user_id":"role_builder","turn_id":"t1","message_id":"m1","name":"Разработчик","started_at":"2026-10-27 10:00:00","seq":0}"#)
        guard case .start(let state) = start else { fatalError("start не разобран") }
        return state
    }

    @objc func testStartCarriesPreallocatedMessageID() {
        let state = started()
        XCTAssertEqual(state.turnID, "t1")
        XCTAssertEqual(state.messageID, "m1")
        XCTAssertEqual(state.seq, 0)
        XCTAssertTrue(state.items.isEmpty)
    }

    @objc func testTextAppendGrowsOnlyTail() {
        var state = started()
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"item_add","item":{"id":"x1","kind":"text","text":"При"}}]}"#)), .applied)
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":2,"ops":[{"op":"text_append","item_id":"x1","text":"вет"}]}"#)), .applied)
        XCTAssertEqual(state.items.map(\.text), ["Привет"])
        XCTAssertEqual(state.seq, 2)
    }

    @objc func testTextReplaceOverwrites() {
        var state = started()
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"item_add","item":{"id":"x1","kind":"text","text":"{\"text\":\"Прив"}}]}"#))
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":2,"ops":[{"op":"text_replace","item_id":"x1","text":"Привет"}]}"#))
        XCTAssertEqual(state.items.first?.text, "Привет")
    }

    @objc func testStepUpdateMergesFields() {
        var state = started()
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"item_add","item":{"id":"s1","kind":"step","tool":"bash","detail":"ls","status":"running","started_at":"2026-10-27 10:00:01"}}]}"#))
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":2,"ops":[{"op":"item_update","item_id":"s1","fields":{"status":"done","ended_at":"2026-10-27 10:00:02","output":"a.txt"}}]}"#))
        let step = state.items[0]
        XCTAssertEqual(step.kind, .step)
        XCTAssertEqual(step.tool, "bash")
        XCTAssertEqual(step.detail, "ls")
        XCTAssertEqual(step.status, "done")
        XCTAssertEqual(step.endedAt, "2026-10-27 10:00:02")
        XCTAssertEqual(step.output, "a.txt")
    }

    @objc func testThinkingPhraseSetAndCleared() {
        var state = started()
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"thinking","phrase":"Смотрю файлы"}]}"#))
        XCTAssertEqual(state.thinking, "Смотрю файлы")
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":2,"ops":[{"op":"thinking","phrase":null}]}"#))
        XCTAssertNil(state.thinking)
    }

    @objc func testBlocksStoredPerItem() {
        var state = started()
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"item_add","item":{"id":"x1","kind":"text","text":"| a |"}},{"op":"blocks","item_id":"x1","blocks":[{"kind":"table","source":"| a |"}]}]}"#))
        XCTAssertNotNil(state.items[0].blocks)
    }

    @objc func testGapAsksForSnapshotAndKeepsState() {
        var state = started()
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"item_add","item":{"id":"x1","kind":"text","text":"А"}}]}"#))
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":3,"ops":[{"op":"text_append","item_id":"x1","text":"Б"}]}"#)), .needsSnapshot)
        XCTAssertEqual(state.items.first?.text, "А")
        XCTAssertEqual(state.seq, 1)
    }

    @objc func testStaleAndForeignEventsIgnored() {
        var state = started()
        _ = state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"item_add","item":{"id":"x1","kind":"text","text":"А"}}]}"#))
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"text_append","item_id":"x1","text":"А"}]}"#)), .ignored)
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t0","seq":2,"ops":[]}"#)), .ignored)
        XCTAssertEqual(state.items.first?.text, "А")
    }

    @objc func testOpOnUnknownItemAsksForSnapshot() {
        var state = started()
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"text_append","item_id":"nope","text":"Б"}]}"#)), .needsSnapshot)
        XCTAssertEqual(state.seq, 0)
    }

    @objc func testEndReturnsMessageID() {
        var state = started()
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:end","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"message_id":"m1"}"#)), .ended(messageID: "m1"))
        XCTAssertTrue(state.isEnded)
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:end","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"message_id":null}"#)), .ignored)
    }

    @objc func testSnapshotRestoresAfterReconnect() throws {
        let json = #"{"chat_id":"c1","user_id":"role_builder","turn_id":"t1","message_id":"m1","seq":7,"name":"Разработчик","started_at":"2026-10-27 10:00:00","items":[{"id":"x1","kind":"text","text":"Готово"}],"thinking":null}"#
        var state = try JSONDecoder().decode(RoleChatLiveTurnState.self, from: Data(json.utf8))
        XCTAssertEqual(state.seq, 7)
        XCTAssertEqual(state.items.map(\.text), ["Готово"])
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":8,"ops":[{"op":"text_append","item_id":"x1","text":"!"}]}"#)), .applied)
        XCTAssertEqual(state.items.map(\.text), ["Готово!"])
    }

    @objc func testUnknownOpIsSkippedNotFatal() {
        var state = started()
        XCTAssertEqual(state.apply(event(#"{"type":"chats:live:patch","chat_id":"c1","user_id":"role_builder","turn_id":"t1","seq":1,"ops":[{"op":"future_op","x":1},{"op":"item_add","item":{"id":"x1","kind":"text","text":"А"}}]}"#)), .applied)
        XCTAssertEqual(state.items.map(\.text), ["А"])
    }
}
