import XCTest
@testable import TaskFlow

final class BranchTabSemanticsTests: XCTestCase {
    private func plan(_ nodes: [[String: Any]]) throws -> ApiCollaborationPlan {
        let payload: [String: Any] = [
            "id": "p", "task_id": "root", "revision": 1, "status": "approved",
            "profile": "manual", "rationale": "", "nodes": nodes, "edges": [],
            "branch_root_task_id": "root",
            "branch_cards": [["id": "root", "tab_number": 0, "responsible_role": "architect"], ["id": "child", "tab_number": 2]],
            "branch_team": [["role_key": "builder", "slot_keys": [], "task_numbers": [0, 2], "execution_state": "active"]]
        ]
        return try JSONDecoder().decode(ApiCollaborationPlan.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    private func node(_ task: String, state: String, skipped: Bool = false) -> [String: Any] {
        var value: [String: Any] = ["slot_key": task, "task_id": task, "role_key": "builder", "required": true,
            "expected_result": "Результат", "execution_state": state]
        if skipped { value["skipped_at"] = "2026-10-12" }
        return value
    }
    func testChildOnlyRoleCannotReceiveHouseFromStaleTeamNumbers() throws {
        let p = try plan([node("child", state: "active")])
        XCTAssertEqual(p.tabNumbers(forRole: "builder"), [2])
    }
    func testRootRoleReceivesHouseAndRealChildNumber() throws {
        let p = try plan([node("root", state: "waiting"), node("child", state: "active")])
        XCTAssertEqual(p.tabNumbers(forRole: "builder"), [0, 2])
    }
    func testSkippedParentStageDoesNotReceiveHouse() throws {
        let p = try plan([node("root", state: "waiting", skipped: true), node("child", state: "active")])
        XCTAssertEqual(p.tabNumbers(forRole: "builder"), [2])
    }
    func testParentAndChildMarkersKeepIndependentStates() throws {
        let p = try plan([node("root", state: "waiting"), node("child", state: "accepted")])
        XCTAssertEqual(p.tabStates(forRole: "builder"), [0: "waiting", 2: "accepted"])
    }
    func testChildActivityMakesBranchActiveWithoutChangingRootStage() throws {
        let p = try plan([node("root", state: "waiting"), node("child", state: "active")])
        XCTAssertEqual(p.branchExecutionState, "active")
        XCTAssertEqual(p.activeChildTaskIDs, ["child"])
        XCTAssertEqual(p.nodes.first?.executionState, "waiting")
    }
    func testCompletedChildrenDoNotPretendParentStagesCompleted() throws {
        let p = try plan([node("root", state: "waiting"), node("child", state: "accepted")])
        XCTAssertEqual(p.branchExecutionState, "waiting")
        XCTAssertTrue(p.activeChildTaskIDs.isEmpty)
    }
    func testResponsibleComesFromBranchCardContract() throws {
        XCTAssertEqual(try plan([]).branchResponsibleRole, "architect")
    }
}
