import XCTest
@testable import TaskFlow

final class TaskLiveStreamTests: XCTestCase {
    func testRealtimeStreamKeepsTaskSlotAndRunIdentity() throws {
        let json = #"{"type":"tasks:live","task_id":"task","subtask_id":"slot-2","run_id":"run-2","complete":false,"turn":{"chat_id":"task","user_id":"role_builder","name":"Разработчик 2","started_at":"2026-10-08T09:00:00Z","thinking":null,"items":[{"kind":"text","text":"Проверяю архив."},{"kind":"step","id":"read1","tool":"read","detail":"archive.ts","status":"running","started_at":"2026-10-08T09:00:00Z"}]}}"#
        guard case .taskLive(let live) = RealtimeEvent.parse(Data(json.utf8)) else {
            return XCTFail("Stream event did not decode")
        }
        XCTAssertEqual(live.taskID, "task")
        XCTAssertEqual(live.subtaskID, "slot-2")
        XCTAssertEqual(live.runID, "run-2")
        XCTAssertFalse(live.complete)
        XCTAssertEqual(live.turn.items.count, 2)
        guard case .text(let text) = live.turn.items[0] else { return XCTFail("Missing text") }
        XCTAssertEqual(text, "Проверяю архив.")
    }

    func testCompletedStreamKeepsTextInsteadOfDisappearing() throws {
        let json = #"{"task_id":"task","subtask_id":null,"run_id":"run","complete":true,"turn":{"chat_id":"task","user_id":"role_architect","name":"Архитектор","items":[{"kind":"text","text":"Готово."}]}}"#
        let live = try JSONDecoder().decode(TaskLiveTurn.self, from: Data(json.utf8))
        XCTAssertTrue(live.complete)
        XCTAssertNil(live.subtaskID)
        XCTAssertEqual(live.turn.items.count, 1)
    }
}
