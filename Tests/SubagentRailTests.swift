import XCTest
@testable import TaskFlow

/// Панель субагентов чата: кто позван, работает ли, куда ведёт портрет.
final class SubagentRailTests: XCTestCase {

    private func message(id: String, room: String?, recipient: String = "role_researcher",
                         status: String = "queued", terminal: Bool = false) throws -> RoleChatMessage {
        let roomField = room.map { "\"child_chat_id\": \"\($0)\"," } ?? ""
        let json = """
        {
          "id": "\(id)",
          "text": "Помощник → Исследователь",
          "is_session_marker": false,
          "created_at": "2026-10-28T10:00:00.000Z",
          "coordination": {
            "requester_name": "Помощник",
            "recipient_name": "Исследователь",
            "recipient_id": "\(recipient)",
            \(roomField)
            "question": "Что в логах?",
            "status": "\(status)",
            "activity": "Работает",
            "created_at": "2026-10-28T10:00:00.000Z",
            "last_activity_at": "2026-10-28T10:00:05.000Z",
            "answer": null,
            "terminal": \(terminal)
          }
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(RoleChatMessage.self, from: json)
    }

    func testRoomBecomesPortraitThatOpensIt() throws {
        let items = SubagentRailItem.items(messages: [try message(id: "c1", room: "room-1")],
                                           members: [], chatID: "chat")
        XCTAssertEqual(items.map(\.id), ["room-1"])
        XCTAssertEqual(items.first?.member.id, "role_researcher")
        XCTAssertEqual(items.first?.member.name, "Исследователь")
        XCTAssertEqual(items.first?.working, true)
    }

    func testCardWithoutOwnRoomIsNotShown() throws {
        let items = SubagentRailItem.items(messages: [try message(id: "c1", room: nil),
                                                      try message(id: "c2", room: "chat")],
                                           members: [], chatID: "chat")
        XCTAssertTrue(items.isEmpty)
    }

    func testFinishedCallShowsOutcome() throws {
        let answered = SubagentRailItem.items(messages: [try message(id: "c1", room: "r1", status: "answered", terminal: true)],
                                              members: [], chatID: "chat")
        XCTAssertEqual(answered.first?.working, false)
        XCTAssertEqual(answered.first?.outcome, .answered)
        let failed = SubagentRailItem.items(messages: [try message(id: "c2", room: "r2", status: "error", terminal: true)],
                                            members: [], chatID: "chat")
        XCTAssertEqual(failed.first?.outcome, .failed)
    }

    func testRoomsKeepOrderOfFirstCall() throws {
        let items = SubagentRailItem.items(messages: [try message(id: "c1", room: "r1"),
                                                      try message(id: "c2", room: "r2", recipient: "role_builder"),
                                                      try message(id: "c3", room: "r1", status: "answered", terminal: true)],
                                           members: [], chatID: "chat")
        XCTAssertEqual(items.map(\.id), ["r1", "r2"])
        XCTAssertEqual(items.first?.outcome, .answered)
    }
}
