import XCTest
@testable import TaskFlow

/// Кэш снимка «Сегодня» — LOCK-OPT-PERF-20261022.
///
/// `TodayComputation` — самая тяжёлая величина на экране «Сегодня»: около
/// двадцати фильтров и шести сортировок по всему списку задач. Раньше снимок
/// собирался заново на каждом проходе `body` (и дважды за проход — тело и
/// тулбар), потому что это было вычисляемое свойство.
///
/// Проверяем три вещи: при неизменных входах снимок собирается ОДИН раз, при
/// изменённых — снова, и содержимое снимка от кэша не отличается от
/// содержимого свежей сборки.
@MainActor
final class TodayComputationCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TodayComputation.buildCount = 0
        TodayComputationCache.shared.reset()
    }

    /// Задачи без проекта (беспроектные) — иначе состав раздела их отсечёт.
    /// Срок по кругу: просрочено → сегодня → впереди → бессрочная.
    private func makeTasks(_ count: Int, today: String = "2026-10-22") -> [ApiTask] {
        (0..<count).map { index in
            let due: String?
            switch index % 4 {
            case 0: due = "2026-10-20"
            case 1: due = today
            case 2: due = "2026-10-25"
            default: due = nil
            }
            return TestTaskFactory.makeTask(
                id: "t\(index)",
                title: "Задача \(index)",
                dueDate: due
            )
        }
    }

    private func makeComputation(
        _ tasks: [ApiTask],
        today: String = "2026-10-22",
        activeHourDate: String = "2026-10-22",
        filters: TodayTaskFilters = .empty,
        tasksRevision: Int = 0
    ) -> TodayComputation {
        TodayComputation(
            allTasks: tasks,
            currentUser: nil,
            agents: [],
            filters: filters,
            showAgentTasks: false,
            visibleProjectIds: [],
            today: today,
            activeHourDate: activeHourDate,
            isLoading: false,
            isError: false,
            tasksRevision: tasksRevision
        )
    }

    // MARK: - Кэш

    func testНеизменныеВходыНеПересобираютСнимок() {
        let tasks = makeTasks(120)
        _ = makeComputation(tasks)
        _ = makeComputation(tasks)
        XCTAssertEqual(
            TodayComputation.buildCount, 1,
            "Снимок с теми же входами должен собираться один раз, а не на каждый проход экрана"
        )
    }

    func testИзменённыеЗадачиПересобираютСнимок() {
        let tasks = makeTasks(20)
        _ = makeComputation(tasks)
        _ = makeComputation(tasks + [TestTaskFactory.makeTask(id: "new", title: "Новая")])
        XCTAssertEqual(TodayComputation.buildCount, 2, "Новая задача обязана пересобрать снимок")
    }

    func testСменаФильтраПересобираетСнимок() {
        let tasks = makeTasks(20)
        _ = makeComputation(tasks)
        _ = makeComputation(tasks, filters: TodayTaskFilters(projectId: "p1"))
        XCTAssertEqual(TodayComputation.buildCount, 2, "Смена фильтра обязана пересобрать снимок")
    }

    func testСменаДняПересобираетСнимок() {
        let tasks = makeTasks(20)
        _ = makeComputation(tasks)
        _ = makeComputation(tasks, today: "2026-10-23", activeHourDate: "2026-10-23")
        XCTAssertEqual(TodayComputation.buildCount, 2, "Другой день — другой снимок")
    }

    /// Содержимое задачи изменилось, а состав списка — тот же: снимок обязан
    /// пересобраться по ревизии стора. Раньше это ловилось сравнением задач
    /// по значению; теперь — ревизией `TaskStore.tasksRevision`.
    func testСменаРевизииПересобираетСнимок() {
        let tasks = makeTasks(20)
        _ = makeComputation(tasks, tasksRevision: 7)
        _ = makeComputation(tasks, tasksRevision: 8)
        XCTAssertEqual(TodayComputation.buildCount, 2, "Правка задачи обязана пересобрать снимок")
    }

    // MARK: - Содержимое не изменилось

    func testРазделыСнимкаНеИзменились() {
        let tasks = makeTasks(8)
        let snapshot = makeComputation(tasks)
        XCTAssertEqual(snapshot.overdueTasks.map(\.id), ["t0", "t4"])
        XCTAssertEqual(snapshot.todayTasks.map(\.id), ["t1", "t5"])
        XCTAssertEqual(snapshot.upcomingTasks.map(\.id), ["t2", "t6"])
        XCTAssertEqual(snapshot.poolTasks.map(\.id), ["t3", "t7"])
        XCTAssertEqual(snapshot.plannerTasks.count, 8)
        XCTAssertFalse(snapshot.trueEmpty)
        XCTAssertFalse(snapshot.filteredEmpty)
    }

    func testОтветИзКэшаСодержимоНеОтличаетсяОтСвежейСборки() {
        let tasks = makeTasks(8)
        let cached = makeComputation(tasks)
        let fresh = TodayComputation(
            allTasks: tasks,
            currentUser: nil,
            agents: [],
            filters: .empty,
            showAgentTasks: false,
            visibleProjectIds: [],
            today: "2026-10-22",
            activeHourDate: "2026-10-22",
            isLoading: false,
            isError: false
        )
        XCTAssertEqual(cached.overdueTasks.map(\.id), fresh.overdueTasks.map(\.id))
        XCTAssertEqual(cached.todayTasks.map(\.id), fresh.todayTasks.map(\.id))
        XCTAssertEqual(cached.upcomingTasks.map(\.id), fresh.upcomingTasks.map(\.id))
        XCTAssertEqual(cached.poolTasks.map(\.id), fresh.poolTasks.map(\.id))
        XCTAssertEqual(cached.hourDays.map(\.date), fresh.hourDays.map(\.date))
        XCTAssertEqual(cached.hourDays.first?.tasks.map(\.id), fresh.hourDays.first?.tasks.map(\.id))
    }
}
