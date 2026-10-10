import XCTest
@testable import TaskFlow
final class SubtaskWorkPlanTests: XCTestCase {
    func testExecutorStatesAndProgress() throws {
        let response = try JSONDecoder().decode(SubtaskWorkPlanResponse.self, from: Data(#"{"plan":{"subtask_id":"s1","revision":2,"updated_at":"2026-10-10T16:00:00Z","items":[{"id":"read","title":"Изучить контракт","state":"done"},{"id":"build","title":"Реализовать","state":"in_progress"},{"id":"verify","title":"Проверить","state":"pending"}]}}"#.utf8))
        let plan = try XCTUnwrap(response.plan)
        XCTAssertEqual(plan.subtaskID, "s1")
        XCTAssertEqual(plan.doneCount, 1)
        XCTAssertEqual(plan.items.map { $0.state.label }, ["Выполнено", "Сейчас", "Ожидает"])
        XCTAssertNil(try JSONDecoder().decode(SubtaskWorkPlanResponse.self, from: Data(#"{"plan":null}"#.utf8)).plan)
    }
}
