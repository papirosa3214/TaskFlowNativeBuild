import XCTest
@testable import TaskFlow

/// Проверяет действующий источник истины списка «Сегодня». Старый
/// `TodaySectionTracker` обслуживал удалённую ручную липкую шапку; теперь
/// SwiftUI закрепляет системные `Section` сам, поэтому тестируем состав и
/// порядок этих секций, а не мёртвую геометрию скролла.
final class TodaySectionInfoTests: XCTestCase {
    private let date = "2026-09-01"

    func testEmptyTasksProduceNoSections() {
        XCTAssertTrue(TodaySectionInfo.list(today: [], todayDate: date).isEmpty)
    }

    /// С 09.09.2026 в списке ровно одна секция — сегодняшний день. «Просрочено»
    /// и «Ждут вас» переехали колонками на доску, поэтому проверяем, что
    /// список их больше не заводит ни при каких данных.
    func testOnlyTodaySectionRemains() {
        let sections = TodaySectionInfo.list(today: [task("today")], todayDate: date)

        XCTAssertEqual(sections.map(\.kind), [.today])
        XCTAssertEqual(sections.map(\.title), [TodayDate.formatDueLabel(date)])
        XCTAssertNil(sections.first?.icon)
    }

    private func task(_ id: String) -> ApiTask {
        TestTaskFactory.makeTask(id: id)
    }
}
