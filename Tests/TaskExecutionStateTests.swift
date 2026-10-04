import XCTest
@testable import TaskFlow

final class TaskExecutionStateTests: XCTestCase {
    func testQueueResponseLocksConflictingActions() throws {
        let json = #"{"status":"queued","busy":true,"scheme":"single","can_launch":false,"can_change_executor":false,"can_use_plan":false,"error":null}"#
        let state = try JSONDecoder().decode(TaskExecutionStatus.self, from: Data(json.utf8))
        XCTAssertEqual(state.title, "Исполнитель в очереди")
        XCTAssertFalse(state.canLaunch)
        XCTAssertFalse(state.canChangeExecutor)
        XCTAssertFalse(state.canUsePlan)
    }
    func testFailurePreservesReasonAndRetry() throws {
        let json = #"{"status":"failed","busy":false,"scheme":"single","can_launch":true,"can_change_executor":false,"can_use_plan":false,"error":"Модель недоступна"}"#
        let state = try JSONDecoder().decode(TaskExecutionStatus.self, from: Data(json.utf8))
        XCTAssertTrue(state.canLaunch)
        XCTAssertEqual(state.error, "Модель недоступна")
    }
}
