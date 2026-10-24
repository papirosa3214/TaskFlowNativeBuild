import XCTest
@testable import TaskFlow

/// Состав и порядок секций списка «Сегодня». Прежний `TodaySectionInfo` —
/// удалённый источник истины ручной липкой шапки; сейчас состав решает
/// `TodayListSection.sections(tab:waiting:overdue:today:upcoming:pool:todayDate:)`,
/// и именно его проверяем. Файл оставлен с историческим именем, чтобы не
/// плодить дубли.
final class TodayListSectionTests: XCTestCase {
    private let date = "2026-09-01"

    func testEmptyTasksProduceNoSections() {
        for tab in TodayListTab.allCases {
            XCTAssertTrue(sections(tab: tab).isEmpty, "вкладка \(tab.rawValue) не должна заводить пустые секции")
        }
    }

    /// Вкладка «Сегодня»: секция дня + «Предстоящие». Пустой «Предстоящие» не
    /// показывается — остаётся только день с его подписью-датой.
    func testTodayTabKeepsOnlyDaySectionWhenUpcomingEmpty() {
        let result = sections(tab: .today, today: [task("today")])

        XCTAssertEqual(result.map(\.id), ["today"])
        XCTAssertEqual(result.first?.title, TodayDate.formatDueLabel(date))
        XCTAssertNil(result.first?.icon)
        XCTAssertEqual(result.first?.marksOverdue, false)
    }

    func testTodayTabShowsUpcomingAfterDay() {
        let result = sections(tab: .today, today: [task("today")], upcoming: [task("soon")])

        XCTAssertEqual(result.map(\.id), ["today", "upcoming"])
        XCTAssertEqual(result.map { $0.tasks.map(\.id) }, [["today"], ["soon"]])
    }

    /// «Ждут вас»: сначала «Ждут вас», затем «Просрочено» с пометкой просрочки.
    func testAttentionTabOrderAndOverdueMark() {
        let result = sections(tab: .attention, waiting: [task("w")], overdue: [task("o")])

        XCTAssertEqual(result.map(\.id), ["waiting", "overdue"])
        XCTAssertEqual(result.first?.title, "Ждут вас")
        XCTAssertEqual(result.last?.title, "Просрочено")
        XCTAssertEqual(result.last?.marksOverdue, true)
    }

    /// «Входящие» — нераспределённые задачи (пул), одна секция.
    func testInboxTabUsesPool() {
        let result = sections(tab: .inbox, pool: [task("p1"), task("p2")])

        XCTAssertEqual(result.map(\.id), ["pool"])
        XCTAssertEqual(result.first?.title, "Входящие")
        XCTAssertEqual(result.first?.tasks.count, 2)
    }

    /// «Ждут вас» вычитаны из остальных наборов на уровне `TodayComputation`,
    /// поэтому здесь секции не пересекаются: каждая рисует свой набор как есть.
    func testAttentionTabDropsEmptySections() {
        let result = sections(tab: .attention, overdue: [task("o")])

        XCTAssertEqual(result.map(\.id), ["overdue"])
    }

    /// Сценарий владельца 18.10.2026: на сегодня задач нет, в «Предстоящих»
    /// есть. Иллюстрация «Чёткое видение грядущего дня» ложилась под ленту
    /// и висела рядом с будущими задачами: `trueEmpty` считал только
    /// сегодняшний день.
    func testTodayTabNotTrulyEmptyWhenOnlyUpcomingHasTasks() {
        let soon = TestTaskFactory.makeTask(id: "soon", dueDate: "2026-09-02")
        let computation = TodayComputation(
            allTasks: [soon], currentUser: nil, agents: [],
            filters: .empty, today: date,
            activeHourDate: date, isLoading: false, isError: false
        )

        XCTAssertTrue(computation.todayTasks.isEmpty)
        XCTAssertEqual(computation.upcomingTasks.map(\.id), ["soon"])
        XCTAssertFalse(computation.trueEmpty, "заглушка не должна рисоваться при непустых «Предстоящих»")
    }

    /// Настоящая пустота — когда задач нет вообще: ни на сегодня, ни впереди.
    func testTodayTabTrulyEmptyWithoutAnyTasks() {
        let computation = TodayComputation(
            allTasks: [], currentUser: nil, agents: [],
            filters: .empty, today: date,
            activeHourDate: date, isLoading: false, isError: false
        )

        XCTAssertTrue(computation.trueEmpty)
    }

    /// «Предстоящие» — подзаголовок вкладки «Сегодня», как «Просрочено» во
    /// вкладке «Ждут вас». Когда сегодняшний день пуст, «Предстоящие»
    /// остаётся единственной секцией, и подпись всё равно нужна: без неё
    /// задачи стоят под названием вкладки и читаются как сегодняшние.
    func testUpcomingSectionKeepsHeaderWhenItIsTheOnlySection() {
        let result = sections(tab: .today, upcoming: [task("soon")])

        XCTAssertEqual(result.map(\.id), ["upcoming"])
        XCTAssertTrue(result[0].showsHeader(among: result))
    }

    /// Единственная секция вкладки без «Предстоящих» заголовок не получает:
    /// он дублировал бы название самой вкладки в шапке. Правило не трогаем.
    func testSingleDaySectionKeepsHeaderInUnifiedList() {
        let result = sections(tab: .today, today: [task("today")])

        XCTAssertEqual(result.map(\.id), ["today"])
        XCTAssertTrue(result[0].showsHeader(among: result))
    }

    func testUnifiedListIncludesEveryBucketInOrder() {
        let result = sections(tab: .today, waiting: [task("w")], overdue: [task("o")],
                              today: [task("t")], upcoming: [task("u")], pool: [task("p")])
        XCTAssertEqual(result.map(\.id), ["pool", "waiting", "overdue", "today", "upcoming"])
        XCTAssertEqual(Set(result.flatMap { $0.tasks.map(\.id) }), Set(["p", "w", "o", "t", "u"]))
    }

    func testProjectlessTasksKeepEveryDateBucketAndWaitingDoesNotDuplicate() {
        let user = try! JSONDecoder().decode(ApiUser.self, from: Data(#"{"id":"u-owner","name":"Owner","role":"owner","type":"human"}"#.utf8))
        let tasks = [TestTaskFactory.makeTask(id: "pool"),
                     TestTaskFactory.makeTask(id: "past", dueDate: "2026-08-31"),
                     TestTaskFactory.makeTask(id: "now", dueDate: date),
                     TestTaskFactory.makeTask(id: "future", dueDate: "2027-01-01"),
                     TestTaskFactory.makeTask(id: "waiting", dueDate: "2026-10-30", agentState: .blocked),
                     TestTaskFactory.makeTask(id: "done", status: .completed)]
        let c = TodayComputation(allTasks: tasks, currentUser: user, agents: [], filters: .empty,
                                 today: date, activeHourDate: date, isLoading: false, isError: false)
        XCTAssertEqual(c.poolTasks.map(\.id), ["pool"])
        XCTAssertEqual(c.overdueTasks.map(\.id), ["past"])
        XCTAssertEqual(c.todayTasks.map(\.id), ["now"])
        XCTAssertEqual(c.upcomingTasks.map(\.id), ["future"])
        XCTAssertEqual(c.waitingTasks.map(\.id), ["waiting"])
    }

    func testFutureRoutineAppearsWithoutCreatingOrDuplicatingTask() {
        let future = RoutineOccurrence(id: "virtual", scheduleId: "s", title: "Routine", timezone: "Europe/Moscow",
            projectId: nil, runAt: "2026-09-02T07:00:00Z", taskId: nil, status: "scheduled", detail: nil)
        let real = RoutineOccurrence(id: "real", scheduleId: "r", title: "Executed", timezone: "Europe/Moscow",
            projectId: nil, runAt: "2026-09-01T07:00:00Z", taskId: "t", status: "created", detail: nil)
        let result = TodayListSection.sections(tab: .today, waiting: [], overdue: [], today: [task("t")],
            upcoming: [], pool: [], todayDate: date, occurrences: [future, real])
        XCTAssertEqual(result.map(\.id), ["today", "upcoming"])
        XCTAssertEqual(result.flatMap(\.occurrences).map(\.id), ["virtual"])
    }

    private func sections(
        tab: TodayListTab,
        waiting: [ApiTask] = [],
        overdue: [ApiTask] = [],
        today: [ApiTask] = [],
        upcoming: [ApiTask] = [],
        pool: [ApiTask] = []
    ) -> [TodayListSection] {
        TodayListSection.sections(
            tab: tab,
            waiting: waiting,
            overdue: overdue,
            today: today,
            upcoming: upcoming,
            pool: pool,
            todayDate: date
        )
    }

    private func task(_ id: String) -> ApiTask {
        TestTaskFactory.makeTask(id: id)
    }
}
