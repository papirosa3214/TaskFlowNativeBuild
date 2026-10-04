import XCTest
@testable import TaskFlow

final class TaskPreparationTests: XCTestCase {
    private func decode(_ status: String, plan: String = "null", planStatus: String = "null", question: String = "null") throws -> ApiTaskPreparation {
        let json = """
        {"id":4,"input_version":2,"status":"\(status)","plan_id":\(plan),"plan_status":\(planStatus),"result":{"question":\(question),"card":{"preparation":{"representation":"child_cards","reason":"Разные результаты","question":null,"workstreams":[{"key":"a","title":"Первый","result":"Документ","role":"researcher","depends_on":[]},{"key":"b","title":"Второй","result":"Отчёт","role":"analyst","depends_on":["a"]}]}}}}
        """
        return try JSONDecoder().decode(ApiTaskPreparation.self, from: Data(json.utf8))
    }
    func testReadyRequiresDraftBeforeExecution() throws {
        XCTAssertTrue(try decode("ready", plan: "\"plan\"", planStatus: "\"draft\"").canApprovePlan)
        XCTAssertFalse(try decode("ready", plan: "\"plan\"", planStatus: "\"approved\"").canApprovePlan)
        XCTAssertFalse(try decode("running", plan: "\"plan\"", planStatus: "\"draft\"").canApprovePlan)
    }
    func testStructureQuestionBlocksApprovalAndDependenciesDecode() throws {
        let proposal = try decode("structure_review")
        XCTAssertTrue(proposal.canApproveStructure)
        XCTAssertEqual(proposal.result?.card?.preparation?.workstreams[1].dependsOn, ["a"])
        XCTAssertFalse(try decode("structure_review", question: "\"Какой регион?\"").canApproveStructure)
    }
}
