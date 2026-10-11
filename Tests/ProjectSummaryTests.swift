import XCTest
@testable import TaskFlow
final class ProjectSummaryTests: XCTestCase {
    func testUnstartedAndStaleTasksAreNotRunning() throws {
        let project = try JSONDecoder().decode(ApiProject.self, from: Data(#"{"id":"p","name":"P","task_count":5,"completed_count":2}"#.utf8))
        let tasks = try JSONDecoder().decode([ApiTask].self, from: Data(#"[{"id":"1","title":"Pending","project_id":"p","status":"active"},{"id":"2","title":"Running","project_id":"p","status":"active","agent_state":"in_progress"},{"id":"3","title":"Stale","project_id":"p","status":"active","agent_state":"in_progress","agent_stale":true},{"id":"4","title":"Review","project_id":"p","status":"active","agent_state":"review"},{"id":"5","title":"Blocked","project_id":"p","status":"active","agent_state":"blocked"}]"#.utf8))
        let value = ProjectTaskStatusSummary(project: project, tasks: tasks)
        XCTAssertEqual(value.total, 7)
        XCTAssertEqual(value.completed, 2)
        XCTAssertEqual(value.inWork, 1)
        XCTAssertEqual(value.pending, 1)
        XCTAssertEqual(value.stale, 1)
        XCTAssertEqual(value.review, 1)
        XCTAssertEqual(value.blocked, 1)
    }
}
