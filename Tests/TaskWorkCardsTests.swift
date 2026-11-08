import XCTest
@testable import TaskFlow

/// Карточки работ в «Все задачи»: задача с ключом инцидента — отдельная группа.
/// Владелец 08.11.2026: «могут находиться под каким-то подзаголовком, который
/// называется Карточки работ, и этого будет более чем достаточно».
final class TaskWorkCardsTests: XCTestCase {
    private struct Item {
        let id: String
        let incidentKey: String?
    }

    func testTaskWithIncidentKeyIsWorkCard() {
        XCTAssertTrue(TaskWorkCards.isWorkCard(incidentKey: "ollama-health"))
    }

    func testNoKeyOrBlankKeyIsOrdinary() {
        XCTAssertFalse(TaskWorkCards.isWorkCard(incidentKey: nil))
        XCTAssertFalse(TaskWorkCards.isWorkCard(incidentKey: ""))
        XCTAssertFalse(TaskWorkCards.isWorkCard(incidentKey: "   "))
    }

    func testSplitKeepsOrderAndSeparatesGroups() {
        let items = [
            Item(id: "a", incidentKey: nil),
            Item(id: "b", incidentKey: "inbox:monitor-110"),
            Item(id: "c", incidentKey: ""),
            Item(id: "d", incidentKey: "work-plan-watch"),
        ]
        let split = TaskWorkCards.split(items, incidentKey: { $0.incidentKey })
        XCTAssertEqual(split.ordinary.map(\.id), ["a", "c"])
        XCTAssertEqual(split.work.map(\.id), ["b", "d"])
    }

    func testEverythingOrdinaryWhenNoIncidents() {
        let items = [Item(id: "a", incidentKey: nil), Item(id: "b", incidentKey: nil)]
        let split = TaskWorkCards.split(items, incidentKey: { $0.incidentKey })
        XCTAssertEqual(split.ordinary.count, 2)
        XCTAssertTrue(split.work.isEmpty)
    }
}
