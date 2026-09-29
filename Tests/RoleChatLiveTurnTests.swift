import Foundation
import XCTest
@testable import TaskFlow

/// Живой ход роли в чате (LOCK-229) — формы как их шлёт сервер
/// (`server/src/runtime/chatLiveTurn.ts`: `chats:live`, `chat_messages.steps`).
final class RoleChatLiveTurnTests: XCTestCase {
    private func parse(_ json: String) -> RealtimeEvent? {
        RealtimeEvent.parse(Data(json.utf8))
    }

    func testPacerPreservesProgressAcrossCumulativeSnapshots() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Привет")])
        pacer.advance()
        XCTAssertEqual(pacer.visibleItems, [.text("Пр")])
        pacer.ingest([.text("Привет, мир")])
        XCTAssertEqual(pacer.visibleItems, [.text("Пр")])
        while pacer.hasPendingText { pacer.advance() }
        XCTAssertEqual(pacer.visibleItems, [.text("Привет, мир")])
    }

    func testPacerShowsStepsAfterPreviousTextAndResetsChangedText() {
        let step = RoleChatLiveStep(id: "s", tool: "read", detail: nil, status: .running)
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Проверяю"), .step(step), .text("Готово")])
        pacer.advance()
        XCTAssertEqual(pacer.visibleItems, [.text("Пр")])
        while pacer.hasPendingText { pacer.advance() }
        XCTAssertEqual(pacer.visibleItems, [.text("Проверяю"), .step(step), .text("Готово")])
        pacer.ingest([.text("Новый ответ")])
        XCTAssertTrue(pacer.visibleItems.isEmpty)
    }

    func testLiveEventCarriesTextAndSteps() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"chat-secretary","user_id":"u-secretary",
         "turn":{"chat_id":"chat-secretary","user_id":"u-secretary","name":"Секретарь",
                 "started_at":"2026-09-27T09:00:00.000Z",
                 "items":[{"kind":"text","text":"Смотрю."},
                          {"kind":"step","id":"c1","tool":"read","detail":"~/a.txt",
                           "status":"running","started_at":"2026-09-27T09:00:01.000Z"}]}}
        """#)
        guard case .roleChatLive(let chatID, let userID, let turn) = event, let turn else {
            return XCTFail("ожидали roleChatLive со снимком, пришло \(String(describing: event))")
        }
        XCTAssertEqual(chatID, "chat-secretary")
        XCTAssertEqual(userID, "u-secretary")
        XCTAssertEqual(turn.name, "Секретарь")
        XCTAssertNotNil(turn.startDate)
        XCTAssertEqual(turn.items, [
            .text("Смотрю."),
            .step(RoleChatLiveStep(id: "c1", tool: "read", detail: "~/a.txt", status: .running)),
        ])
    }

    func testLiveEventWithNullTurnMeansFinished() {
        let event = parse(#"""
        {"type":"chats:live","chat_id":"chat-1","user_id":"role_qa","turn":null}
        """#)
        guard case .roleChatLive(_, let userID, let turn) = event else {
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
        guard case .roleChatLive(_, _, let turn) = event, let turn else {
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
        XCTAssertEqual(RoleLiveStepKind.label(forTool: "taskflow_create_task"), "Действие")
    }
}
