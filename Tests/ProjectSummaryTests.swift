import Foundation
import XCTest
@testable import TaskFlow

final class ProjectSummaryTests: XCTestCase {
    private func project(active: Int = 999, completed: Int = 999) throws -> ApiProject {
        try JSONDecoder().decode(ApiProject.self, from: Data("{\"id\":\"p\",\"name\":\"P\",\"task_count\":\(active),\"completed_count\":\(completed)}".utf8))
    }

    private func task(_ id: String, state: String? = nil, branch: String? = nil,
                      completed: Bool = false, stale: Bool = false,
                      projectID: String = "p", archived: Bool = false) throws -> ApiTask {
        var json: [String: Any] = ["id": id, "title": id, "priority": 4, "project_id": projectID,
                                   "status": completed ? "completed" : "active", "agent_stale": stale]
        json["agent_state"] = state
        json["branch_agent_state"] = branch
        json["archived_at"] = archived ? "2026-10-30 10:00:00" : nil
        return try JSONDecoder().decode(ApiTask.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testOwnerExampleTenTasksTwoCompletedMeansTwentyPercent() throws {
        var tasks = try (1...5).map { try task("waiting\($0)") }
        tasks += try (1...2).map { try task("done\($0)", completed: true) }
        tasks += try (1...3).map { try task("blocked\($0)", state: "blocked") }
        // Projects and tasks can arrive at different times. Only one snapshot owns the numbers.
        let value = ProjectTaskStatusSummary(project: try project(), tasks: tasks)
        XCTAssertEqual(value.total, 10)
        XCTAssertEqual(value.completed, 2)
        XCTAssertEqual(value.pending, 5)
        XCTAssertEqual(value.blocked, 3)
        XCTAssertEqual(value.inWork, 0)
        XCTAssertEqual(value.review, 0)
        XCTAssertEqual(Double(value.completed) / Double(value.total), 0.2, accuracy: 0.0001)
    }

    func testAllFourActiveStatesUseTheSameEffectiveStateAsTaskLists() throws {
        let tasks = try [task("running", branch: "in_progress"),
                         task("review", branch: "review"), task("blocked", branch: "blocked"),
                         task("waiting"), task("queued", state: "todo"),
                         task("own-wins", state: "blocked", branch: "in_progress")]
        let value = ProjectTaskStatusSummary(project: try project(), tasks: tasks)
        XCTAssertEqual(value.total, 6)
        XCTAssertEqual(value.inWork, 1)
        XCTAssertEqual(value.review, 1)
        XCTAssertEqual(value.blocked, 2)
        XCTAssertEqual(value.pending, 2)
        XCTAssertEqual(value.completed, 0)
    }

    func testHeartbeatAgeDoesNotCreateAHiddenFifthActiveCategory() throws {
        let value = ProjectTaskStatusSummary(project: try project(), tasks: [
            try task("stale", state: "in_progress", stale: true)])
        // Heartbeat is a diagnostic flag; the task itself is still in_progress.
        XCTAssertEqual(value.inWork, 1)
        XCTAssertEqual(value.total, value.inWork + value.review + value.blocked + value.pending + value.completed)
    }

    func testCompletedArchivedAndOtherProjectStatesCannotInflateActiveBadges() throws {
        let value = ProjectTaskStatusSummary(project: try project(), tasks: [
            try task("completed", state: "blocked", completed: true),
            try task("archived", state: "review", archived: true),
            try task("other", state: "in_progress", projectID: "another")])
        XCTAssertEqual(value.total, 1)
        XCTAssertEqual(value.completed, 1)
        XCTAssertEqual(value.inWork + value.review + value.blocked + value.pending, 0)
    }

    func testEmptyProjectDoesNotReuseOldServerAggregates() throws {
        let value = ProjectTaskStatusSummary(project: try project(active: 10, completed: 20), tasks: [])
        XCTAssertEqual(value.total, 0)
        XCTAssertEqual(value.completed, 0)
        XCTAssertEqual(value.pending, 0)
    }

    func testRealtimeMoveCompletionAndReopenRecomputeAllCounts() throws {
        let p = try project(active: 0, completed: 0)
        let open = ProjectTaskStatusSummary(project: p, tasks: [try task("one")])
        XCTAssertEqual(open.total, 1)
        XCTAssertEqual(open.pending, 1)
        let done = ProjectTaskStatusSummary(project: p, tasks: [try task("one", completed: true)])
        XCTAssertEqual(done.total, 1)
        XCTAssertEqual(done.completed, 1)
        XCTAssertEqual(done.pending, 0)
        let reopened = ProjectTaskStatusSummary(project: p, tasks: [try task("one", state: "review")])
        XCTAssertEqual(reopened.total, 1)
        XCTAssertEqual(reopened.completed, 0)
        XCTAssertEqual(reopened.review, 1)
        let moved = ProjectTaskStatusSummary(project: p, tasks: [try task("one", projectID: "another")])
        XCTAssertEqual(moved.total, 0)
    }
}
