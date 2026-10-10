import XCTest
@testable import TaskFlow

final class RoleLoadTests: XCTestCase {
    func testAllRolesAndUnassignedSlotsRemainVisible() throws {
        let json = #"{"window":"24h","from":"2026-10-09T12:00:00.000Z","to":"2026-10-10T12:00:00.000Z","now":"2026-10-10T12:00:00.000Z","roles":[{"key":"builder","title":"Разработчик","position":2},{"key":"critic","title":"Критик","position":1}],"attempts":[],"active_now":[],"open_slots":[{"id":"t1","task_title":"Задача","role_key":null,"state":"free"}]}"#
        let model = try JSONDecoder().decode(RoleLoad.self, from: Data(json.utf8))
        XCTAssertEqual(model.rows.map(\.title), ["Критик", "Разработчик", "Без роли"])
        XCTAssertEqual(model.rows.last?.open.first?.id, "t1")
        XCTAssertEqual(model.fraction("2026-10-10T00:00:00Z"), 0.5, accuracy: 0.001)
        XCTAssertEqual(model.fraction("2026-10-01T00:00:00Z"), 0)
        XCTAssertEqual(model.fraction("2026-10-11T00:00:00Z"), 1)
    }
}
