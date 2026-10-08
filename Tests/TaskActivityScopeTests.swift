import XCTest
@testable import TaskFlow

final class TaskActivityScopeTests: XCTestCase {
    func testParallelSlotsNeverUseSharedTotal() throws {
        let data = Data(#"{"text":"shared","total":220,"actions":[],"by_subtask":{"server":{"text":"server","total":17,"actions":[]},"web":{"text":"web","total":8,"actions":[]}}}"#.utf8)
        let activity = try JSONDecoder().decode(ApiTaskActivity.self, from: data)
        XCTAssertEqual(activity.forSubtask("server").total, 17)
        XCTAssertEqual(activity.forSubtask("web").total, 8)
        XCTAssertEqual(activity.forSubtask("server").text, "server")
        XCTAssertEqual(activity.forSubtask("missing"), .idle)
    }
    func testLegacyServerDoesNotPresentTaskTotalAsExecutorTotal() throws {
        let activity = try JSONDecoder().decode(ApiTaskActivity.self, from: Data(#"{"text":"shared","total":220,"actions":[]}"#.utf8))
        XCTAssertEqual(activity.forSubtask("server"), .idle)
    }
}
