import XCTest
@testable import TaskFlow

final class OwnerControlsDecodingTests: XCTestCase {
    func testRuntimeStatusCountsStuckSteps() throws {
        let json = #"{"active_runs":2,"stuck":[{"subtask_id":"a","task_id":"t","title":"x","heartbeat_at":null},{"subtask_id":"b","task_id":"t","title":"y","heartbeat_at":"2026-10-06 01:44:05"}]}"#
        let status = try JSONDecoder().decode(OwnerRuntimeStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.activeRuns, 2)
        XCTAssertEqual(status.stuckCount, 2)
    }

    func testRuntimeStatusWithoutStuckKeyIsZero() throws {
        let json = #"{"active_runs":0}"#
        let status = try JSONDecoder().decode(OwnerRuntimeStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.stuckCount, 0)
    }

    func testResumeResultAndRestartAck() throws {
        let resume = try JSONDecoder().decode(
            OwnerResumeResult.self,
            from: Data(#"{"found":3,"resumed":2,"blocked":1,"freed":0}"#.utf8)
        )
        XCTAssertEqual(resume.found, 3)
        XCTAssertEqual(resume.resumed, 2)
        XCTAssertEqual(resume.blocked, 1)
        let ack = try JSONDecoder().decode(
            OwnerRestartAck.self,
            from: Data(#"{"accepted":true,"active_runs":3}"#.utf8)
        )
        XCTAssertTrue(ack.accepted)
        XCTAssertEqual(ack.activeRuns, 3)
    }
}
