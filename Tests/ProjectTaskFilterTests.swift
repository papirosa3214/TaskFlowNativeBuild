import XCTest
@testable import TaskFlow
final class ProjectTaskFilterTests: XCTestCase {
    private func task(_ state: String? = nil, branch: String? = nil, completed: Bool = false, assigned: Bool = false) throws -> ApiTask {
        var json: [String: Any] = ["id": "t", "title": "Task", "priority": 4, "status": completed ? "completed" : "active"]
        json["agent_state"] = state
        json["branch_agent_state"] = branch
        json["assignee_id"] = assigned ? "role_qa" : nil
        return try JSONDecoder().decode(ApiTask.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func testWaitingIncludesUnassignedAndQueuedButNotWorkingOrBlockedOrReview() throws {
        let waiting = ProjectTaskFilter(rawValue: "waiting") ?? .open
        XCTAssertTrue(waiting.matches(try task()))
        XCTAssertTrue(waiting.matches(try task(assigned: true)))
        XCTAssertTrue(waiting.matches(try task("todo")))
        for state in ["in_progress", "blocked", "review"] {
            XCTAssertFalse(waiting.matches(try task(state)))
            XCTAssertFalse(waiting.matches(try task(branch: state)))
        }
        XCTAssertFalse(waiting.matches(try task(completed: true)))
    }
    func testBlockedExcludesQueueAndUsesBranchState() throws {
        let blocked = ProjectTaskFilter(rawValue: "blocked") ?? .stuck
        XCTAssertTrue(blocked.matches(try task("blocked")))
        XCTAssertTrue(blocked.matches(try task(branch: "blocked")))
        XCTAssertFalse(blocked.matches(try task("todo")))
        XCTAssertFalse(blocked.matches(try task("blocked", completed: true)))
    }
    func testReviewAndWorkingUseEffectiveState() throws {
        XCTAssertTrue(ProjectTaskFilter.review.matches(try task(branch: "review")))
        XCTAssertTrue(ProjectTaskFilter.working.matches(try task(branch: "in_progress")))
        XCTAssertFalse(ProjectTaskFilter.review.matches(try task("blocked", branch: "review")))
        XCTAssertFalse(ProjectTaskFilter.review.matches(try task("review", completed: true)))
    }
    func testFourStatusesPartitionActiveTasksAndSelectionReplacesPrevious() throws {
        let filters = ["working", "review", "blocked", "waiting"].compactMap(ProjectTaskFilter.init(rawValue:))
        XCTAssertEqual(filters.count, 4)
        for state in [nil, "todo", "in_progress", "blocked", "review"] as [String?] {
            for branch in [nil, "in_progress", "blocked", "review"] as [String?] {
                let active = try task(state, branch: branch)
                XCTAssertEqual(filters.filter { $0.matches(active) }.count, 1)
                let completed = try task(state, branch: branch, completed: true)
                XCTAssertTrue(filters.allSatisfy { !$0.matches(completed) })
            }
        }
        let source = try [task("in_progress"), task("review"), task("blocked"), task("todo"), task(completed: true)]
        var selection = ProjectTaskFilter.working
        XCTAssertEqual(source.filter(selection.matches).count, 1)
        selection = .review
        XCTAssertEqual(source.filter(selection.matches).map(\.agentState), [.review])
        selection = ProjectTaskFilter(rawValue: "waiting") ?? .open
        XCTAssertEqual(source.filter(selection.matches).map(\.agentState), [.todo])
    }

    func testOrdinaryViewsAndUnassignedTasksRemainAvailable() throws {
        XCTAssertTrue(ProjectTaskFilter.open.matches(try task()))
        XCTAssertTrue(ProjectTaskFilter.all.matches(try task(completed: true)))
        XCTAssertFalse(ProjectTaskFilter.open.matches(try task(completed: true)))
        XCTAssertTrue(ProjectTaskFilter.done.matches(try task(completed: true)))
    }
}
