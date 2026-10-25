import XCTest
@testable import TaskFlow

final class TaskJournalVisibilityTests: XCTestCase {
    private func event(_ id: String, kind: String, field: String? = nil, value: String? = nil) -> ApiTaskEvent {
        ApiTaskEvent(id: id, taskId: "task", actorId: "role_architect", actorName: "Архитектор", kind: kind, field: field, fromValue: nil, toValue: value, createdAt: "2026-10-24 20:00:00")
    }

    func testJournalOmitsRoutineEventsAndUnknownFallbacks() {
        let events = [
            event("snapshot", kind: "instruction_snapshot"),
            event("context", kind: "collaboration_context_used"),
            event("heartbeat", kind: "heartbeat"),
            event("role", kind: "role_choice", value: "Роль подобрана по сути работы"),
            event("ready", kind: "ready_flag_changed", value: "1"),
            event("unknown", kind: "future_internal_event"),
            event("field", kind: "field_changed", field: "internal_counter", value: "2")
        ]
        XCTAssertTrue(TaskJournalEntry.merged(comments: [], events: events).isEmpty)
        XCTAssertEqual(events.count, 7, "Presentation must not delete the source audit")
    }

    func testJournalKeepsResultsDecisionsAndSpecificChanges() {
        let events = [
            event("blocked", kind: "state_changed", value: "blocked"),
            event("review", kind: "review_recorded"),
            event("result", kind: "result_version_created"),
            event("done", kind: "subtask_done", value: "Исправлен чат"),
            event("deadline", kind: "field_changed", field: "due_date", value: "2026-10-25")
        ]
        let rows = TaskJournalEntry.merged(comments: [], events: events)
        XCTAssertEqual(Set(rows.map(\.id)), Set(events.map { "e-" + $0.id }))
    }

    func testJournalKeepsCommentsEvenWhenTextMentionsServiceEvents() throws {
        let json = #"{"id":"owner","text":"Архитектор обновил задачу — это мой комментарий","created_at":"2026-10-24 20:00:01"}"#
        let comment = try JSONDecoder().decode(ApiComment.self, from: Data(json.utf8))
        let rows = TaskJournalEntry.merged(comments: [comment], events: [event("noise", kind: "heartbeat")])
        XCTAssertEqual(rows.map(\.id), ["c-owner"])
    }
}
