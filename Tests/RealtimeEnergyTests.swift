import XCTest
@testable import TaskFlow

@MainActor
final class RealtimeEnergyTests: XCTestCase {
    func testWrappedServerTaskEventDecodes() {
        let data = Data(#"{"type":"task:updated","task":{"id":"card","title":"Работа","status":"active","subtasks":[]}}"#.utf8)
        guard case .taskUpdated(let task) = RealtimeEvent.parse(data) else {
            return XCTFail("Server envelope must update the card without polling")
        }
        XCTAssertEqual(task.id, "card")
    }

    func testOnlyAffectedCardWakesAndReconnectRestoresAllCards() {
        let client = RealtimeClient()
        client.record(.taskChanged(taskID: "card"))
        XCTAssertEqual(client.revision(for: "card"), 1)
        XCTAssertEqual(client.revision(for: "other"), 0)
        client.record(.connected)
        // С 27.10.2026 переподключение сокета само по себе карточку не будит
        // (3d1d1c33): после дельты /api/tasks/changes будится только названная
        // в ней карточка, а без дельты — все.
        XCTAssertEqual(client.revision(for: "card"), 1)
        XCTAssertEqual(client.revision(for: "other"), 0)
        client.recordCatchUp(changedTaskIDs: ["card"])
        XCTAssertEqual(client.revision(for: "card"), 2, "дельта будит названную карточку")
        XCTAssertEqual(client.revision(for: "other"), 0, "остальные карточки не будит")
        client.recordCatchUp(changedTaskIDs: nil)
        XCTAssertEqual(client.revision(for: "other"), 1, "без дельты просыпаются все карточки")
    }

    func testActivitySignalDoesNotReloadTheWholePlan() {
        let client = RealtimeClient()
        client.record(.taskActivity(taskId: "card", raw: .null))
        XCTAssertEqual(client.activityRevisions["card"], 1)
        XCTAssertEqual(client.revision(for: "card"), 0)
    }

    func testMissingActivityStillCancelsItsObserver() async {
        let observer = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }
        LiveActivityService.activityObservers["already-dismissed"] = observer
        await LiveActivityService.end(taskID: "already-dismissed")
        XCTAssertTrue(observer.isCancelled)
        XCTAssertNil(LiveActivityService.activityObservers["already-dismissed"])
    }

    func testTaskInvalidationIsRecognizedWithoutFullTaskPayload() {
        let data = Data(#"{"type":"task:changed","task_id":"card"}"#.utf8)
        guard let event = RealtimeEvent.parse(data) else { return XCTFail("Missing event") }
        if case .unknown = event { XCTFail("Preparation/plan invalidation must reach the card") }
    }
}
