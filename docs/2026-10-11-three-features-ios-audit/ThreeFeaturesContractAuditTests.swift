import XCTest
@testable import TaskFlow

final class ThreeFeaturesContractAuditTests: XCTestCase {
    func testV2DeliveryResponseCurrentlyFailsAtObsoleteWakeConfirmedField() {
        let data = Data(#"{"delivered":true,"http_status":200,"wake":{"codex_thread_id":"audit","has_thread":true,"queued":true,"codex_followup_id":"f1","acked":false,"acked_at":null,"error":null},"error":null}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(WebhookTestResult.self, from: data)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(key.stringValue, "wake_confirmed")
        }
    }
    func testV2AcknowledgementAndQueuedTimestampAreCurrentlyIgnored() throws {
        let data = Data(#"{"id":"h1","name":"Audit","url":"http://127.0.0.1","enabled":true,"event_kinds":[],"last_wake_at":"2026-10-11T00:00:01Z","wake":{"codex_thread_id":"audit","has_thread":true},"last_wake_ack":{"acked":true,"acked_at":"2026-10-11T00:00:02Z","codex_followup_id":"f1","kind":"turn_started"}}"#.utf8)
        let hook = try JSONDecoder().decode(TaskFlowWebhook.self, from: data)
        XCTAssertNil(hook.wakeConfirmedAt)
        XCTAssertNil(hook.wake?.lastWakeAt)
        XCTAssertEqual(hook.wake?.codexThreadID, "audit")
    }
}
