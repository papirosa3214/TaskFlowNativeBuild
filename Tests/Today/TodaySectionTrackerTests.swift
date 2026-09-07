import XCTest
@testable import TaskFlow

/// Проверяет действующий источник истины списка «Сегодня». Старый
/// `TodaySectionTracker` обслуживал удалённую ручную липкую шапку; теперь
/// SwiftUI закрепляет системные `Section` сам, поэтому тестируем состав и
/// порядок этих секций, а не мёртвую геометрию скролла.
final class TodaySectionInfoTests: XCTestCase {
    private let date = "2026-09-01"

    func testEmptyTasksProduceNoSections() {
        XCTAssertTrue(TodaySectionInfo.list(waiting: [], overdue: [], today: [], todayDate: date).isEmpty)
    }

    func testSectionsStayInProductOrder() {
        let sections = TodaySectionInfo.list(
            waiting: [task("waiting")],
            overdue: [task("overdue")],
            today: [task("today")],
            todayDate: date
        )

        XCTAssertEqual(sections.map(\.kind), [.overdue, .waiting, .today])
        XCTAssertEqual(sections.map(\.title), ["Просрочено", "Ждут вас", TodayDate.formatDueLabel(date)])
    }

    func testSparseSectionsDoNotLeavePlaceholders() {
        let sections = TodaySectionInfo.list(
            waiting: [],
            overdue: [task("overdue")],
            today: [],
            todayDate: date
        )

        XCTAssertEqual(sections.map(\.kind), [.overdue])
        XCTAssertEqual(sections.first?.icon, "exclamationmark")
    }

    private func task(_ id: String) -> ApiTask {
        TestTaskFactory.makeTask(id: id)
    }
}
