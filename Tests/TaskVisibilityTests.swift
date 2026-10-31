import XCTest
@testable import TaskFlow

/// Правила видимости задач (владелец, 01.11.2026): «в архив уходят отменённые
/// и выполненные, карточка одинаковая, единственная пометка — отменённая либо
/// выполненная. Из всех остальных списков убрать».
final class TaskVisibilityTests: XCTestCase {

    /// Задача с сервера — из JSON, как в жизни (см. TaskDueDateTests).
    private func task(status: String = "active", archived: Bool = false) -> ApiTask {
        let payload: [String: Any] = [
            "id": "task-1",
            "title": "Задача",
            "status": status,
            "priority": 0,
            "archived_at": archived ? "2026-11-01 10:00:00" : NSNull(),
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(ApiTask.self, from: data)
    }

    /// Закрытая задача не показывается в живых списках.
    func testClosedTaskIsNotLive() {
        XCTAssertFalse(TaskVisibility.isLive(task(status: "completed")))
        XCTAssertFalse(TaskVisibility.isLive(task(archived: true)))
        XCTAssertTrue(TaskVisibility.isLive(task()))
    }

    /// Живой список отсекает закрытые задачи.
    func testLiveTasksDropClosed() {
        let live = task()
        let closed = task(status: "completed")
        let archived = task(archived: true)
        let result = TaskVisibility.liveTasks([live, closed, archived])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, live.id)
    }

    /// Закрытая карточка — выполненная или отменённая.
    func testClosedDetection() {
        XCTAssertTrue(TaskVisibility.isClosed(task(status: "completed")))
        XCTAssertTrue(TaskVisibility.isClosed(task(archived: true)))
        XCTAssertFalse(TaskVisibility.isClosed(task()))
    }

    /// Пометка в архивной карточке: единственная разница между двумя видами.
    func testOutcomeLabel() {
        XCTAssertEqual(TaskVisibility.outcomeLabel(task(status: "completed")), "Выполнена")
        XCTAssertEqual(TaskVisibility.outcomeLabel(task(archived: true)), "Отменена")
    }
}
