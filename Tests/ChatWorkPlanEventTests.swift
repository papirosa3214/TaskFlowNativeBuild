import XCTest
@testable import TaskFlow

/// План из события `chat:work_plan` ложится в полосу без повторного запроса
/// (владелец 27.10.2026).
final class ChatWorkPlanEventTests: XCTestCase {
    private func payload(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func plan(_ role: String, revision: Int, title: String) -> ChatWorkPlan {
        ChatWorkPlan(chatID: "c1", roleID: role, revision: revision,
                     items: [.init(id: "a", title: title, state: .pending)], updatedAt: "2026-10-27T00:00:00Z")
    }

    private func event(role: String, revision: Int, title: String, chat: String = "c1") -> String {
        #"{"type":"chat:work_plan","chat_id":"\#(chat)","plan":{"chat_id":"\#(chat)","role_id":"\#(role)","revision":\#(revision),"updated_at":"2026-10-27T01:00:00Z","items":[{"id":"a","title":"\#(title)","state":"in_progress"}]}}"#
    }

    func testReplacesPlanOfSameRoleInPlace() throws {
        let start = [plan("r1", revision: 1, title: "старое"), plan("r2", revision: 1, title: "другое")]
        let result = try XCTUnwrap(ChatWorkPlan.applyingEvent(payload(event(role: "r1", revision: 2, title: "новое")), chatID: "c1", to: start))
        XCTAssertEqual(result.map(\.roleID), ["r1", "r2"])
        XCTAssertEqual(result[0].items.first?.title, "новое")
        XCTAssertEqual(result[0].items.first?.state, .inProgress)
    }

    func testAppendsPlanOfNewRole() throws {
        let result = try XCTUnwrap(ChatWorkPlan.applyingEvent(payload(event(role: "r2", revision: 1, title: "x")), chatID: "c1", to: [plan("r1", revision: 1, title: "y")]))
        XCTAssertEqual(result.map(\.roleID), ["r1", "r2"])
    }

    func testResetRemovesRow() throws {
        let reset = #"{"chat_id":"c1","plan":{"chat_id":"c1","role_id":"r1","revision":0,"items":[]}}"#
        let result = try XCTUnwrap(ChatWorkPlan.applyingEvent(payload(reset), chatID: "c1", to: [plan("r1", revision: 3, title: "y")]))
        XCTAssertTrue(result.isEmpty)
    }

    func testIgnoresOtherChatAndStaleRevision() throws {
        XCTAssertNil(ChatWorkPlan.applyingEvent(try payload(event(role: "r1", revision: 9, title: "x", chat: "c2")), chatID: "c1", to: []))
        let stale = try XCTUnwrap(ChatWorkPlan.applyingEvent(payload(event(role: "r1", revision: 1, title: "старое")), chatID: "c1", to: [plan("r1", revision: 5, title: "свежее")]))
        XCTAssertEqual(stale[0].items.first?.title, "свежее")
    }
}
