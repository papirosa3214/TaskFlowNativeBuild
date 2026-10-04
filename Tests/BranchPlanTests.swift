import XCTest
@testable import TaskFlow

final class BranchPlanTests: XCTestCase {
    func testBranchGraphKeepsCardAndExecutableSlotIdentitySeparate() throws {
        let data = Data("""
        {"id":"root-plan","task_id":"root","revision":2,"status":"draft","profile":"single_executor","rationale":"Общая ветка","branch_snapshot":"snapshot-1","branch_root_task_id":"root","nodes":[{"slot_key":"child:work","role_key":"builder","required":true,"expected_result":"Документ","task_id":"child","task_title":"Дочерний результат","source_plan_id":"child-plan","source_slot_key":"work","execution_state":"waiting","responsible":true}],"edges":[]}
        """.utf8)
        let plan = try JSONDecoder().decode(ApiCollaborationPlan.self, from: data)
        XCTAssertEqual(plan.branchSnapshot, "snapshot-1")
        XCTAssertEqual(plan.nodes.first?.sourceSlotKey, "work")
        XCTAssertEqual(plan.nodes.first?.taskId, "child")
        XCTAssertEqual(plan.nodes.first?.responsible, true)
    }
    func testOldStandalonePlanStillDecodes() throws {
        let data = Data("""
        {"id":"old","task_id":"task","revision":1,"status":"draft","profile":"manual","rationale":"","nodes":[{"slot_key":"work","role_key":"builder","required":true,"expected_result":"Итог"}],"edges":[]}
        """.utf8)
        let plan = try JSONDecoder().decode(ApiCollaborationPlan.self, from: data)
        XCTAssertNil(plan.branchSnapshot)
        XCTAssertNil(plan.nodes.first?.executionState)
    }
}
