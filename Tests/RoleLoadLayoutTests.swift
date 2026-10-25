import XCTest
@testable import TaskFlow

final class RoleLoadLayoutTests: XCTestCase {
    private func model(_ json: String) throws -> RoleLoad {
        try JSONDecoder().decode(RoleLoad.self, from: Data(json.utf8))
    }

    private func payload(
        attempts: [String],
        active: [String] = [],
        open: [String] = [],
        chat: [String] = []
    ) -> String {
        """
        {"window":"24h","from":"2026-10-21T00:00:00.000Z","to":"2026-10-22T00:00:00.000Z",
         "now":"2026-10-21T12:00:00.000Z",
         "roles":[{"key":"builder","title":"Разработчик","position":1}],
         "attempts":[\(attempts.joined(separator: ","))],
         "active_now":[\(active.joined(separator: ","))],
         "open_slots":[\(open.joined(separator: ","))],
         "chat_turns":[\(chat.joined(separator: ","))]}
        """
    }

    private func chatTurn(
        id: String,
        title: String,
        chat: String = "Чат про TaskFlow",
        from: String,
        to: String
    ) -> String {
        """
        {"id":"\(id)","chat_id":"c1","chat_title":"\(chat)","role_id":"role_builder",
         "role_key":"builder","started_at":"\(from)","ended_at":"\(to)","title":"\(title)"}
        """
    }

    private func attempt(
        id: String,
        task: String,
        title: String = "Задача",
        created: String = "2026-10-12 10:10:00",
        from: String,
        to: String? = nil,
        outcome: String = "done",
        active: Bool = false
    ) -> String {
        """
        {"id":"\(id)","task_id":"\(task)","task_title":"\(title)","task_created_at":"\(created)",
         "subtask_id":null,"routing_role":"builder","started_at":"\(from)",
         "ended_at":\(to.map { "\"\($0)\"" } ?? "null"),
         "outcome":\(outcome.isEmpty ? "null" : "\"\(outcome)\""),
         "active":\(active)}
        """
    }

    /// Несколько заходов одной задачи — один контур, а не несколько строк.
    func testSeveralAttemptsOfOneTaskBecomeOneContour() throws {
        let json = payload(attempts: [
            attempt(id: "a1", task: "t1", from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T09:10:00.000Z"),
            attempt(id: "a2", task: "t1", from: "2026-10-21T09:20:00.000Z", to: "2026-10-21T09:30:00.000Z"),
        ])
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertEqual(row.lanes.count, 1)
        XCTAssertEqual(row.lanes[0].contours.count, 1)
        XCTAssertEqual(row.lanes[0].contours[0].segments.count, 2)
    }

    /// Контур охватывает все заходы задачи — от первого до последнего.
    func testContourSpansFromFirstToLastAttempt() throws {
        let json = payload(attempts: [
            attempt(id: "a1", task: "t1", from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T09:10:00.000Z"),
            attempt(id: "a2", task: "t1", from: "2026-10-21T11:00:00.000Z", to: "2026-10-21T11:10:00.000Z"),
        ])
        let data = try model(json)
        let layout = RoleLoadLayout.build(data, width: 1000)
        let contour = try XCTUnwrap(layout.first?.lanes[0].contours.first)
        let width: CGFloat = 1000
        let firstStart = width * CGFloat(data.fraction("2026-10-21T09:00:00.000Z"))
        let lastStart = width * CGFloat(data.fraction("2026-10-21T11:00:00.000Z"))
        let lastEnd = width * CGFloat(data.fraction("2026-10-21T11:10:00.000Z"))
        XCTAssertEqual(contour.start, firstStart, accuracy: 0.01)
        // Короткий заход (10 минут ≈ 7 pt) рисуется от минимальной ширины
        // полосы — иначе его не видно. Контур доходит до её правого края.
        XCTAssertEqual(contour.end, max(lastStart + RoleLoadLayout.minBarWidth, lastEnd), accuracy: 0.01)
        XCTAssertGreaterThan(contour.end, lastEnd, "контур должен ширить короткий заход до видимого")
    }

    /// Ключевое: разные задачи, не пересекающиеся по времени, встают в одну
    /// дорожку — высота графика не растёт от числа задач.
    func testNonOverlappingTasksShareOneLane() throws {
        let json = payload(attempts: [
            attempt(id: "a1", task: "t1", from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T09:10:00.000Z"),
            attempt(id: "a2", task: "t2", title: "Другая", from: "2026-10-21T10:00:00.000Z", to: "2026-10-21T10:10:00.000Z"),
        ])
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertEqual(row.lanes.count, 1, "непересекающиеся задачи должны делить дорожку")
        XCTAssertEqual(row.lanes[0].contours.count, 2)
    }

    /// Пересекающиеся по времени задачи — в разные дорожки.
    func testOverlappingTasksGoToDifferentLanes() throws {
        let json = payload(attempts: [
            attempt(id: "a1", task: "t1", from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T10:00:00.000Z"),
            attempt(id: "a2", task: "t2", title: "Другая", from: "2026-10-21T09:30:00.000Z", to: "2026-10-21T10:30:00.000Z"),
        ])
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertEqual(row.lanes.count, 2, "пересекающиеся задачи не могут делить дорожку")
    }

    /// Номер задачи — из момента её создания.
    func testContourCarriesTaskNumber() throws {
        let json = payload(attempts: [
            attempt(id: "a1", task: "t1", created: "2026-10-12 10:10:00", from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T09:10:00.000Z"),
        ])
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        XCTAssertEqual(layout.first?.lanes[0].contours[0].number, "МАК-1210-1310")
    }

    /// «Идёт сейчас» не рисуется второй полосой: если по задаче уже есть
    /// незакрытая попытка, отдельный брусок не создаётся.
    func testActiveSlotWithOpenAttemptDoesNotDuplicateBar() throws {
        let json = payload(
            attempts: [attempt(id: "a1", task: "t1", from: "2026-10-21T11:00:00.000Z", to: nil, outcome: "", active: true)],
            active: ["""
            {"id":"s1","task_id":"t1","task_title":"Задача","task_created_at":"2026-10-12 10:10:00",
             "role_key":"builder","started_at":"2026-10-21T11:00:00.000Z","heartbeat_at":"2026-10-21T11:50:00.000Z"}
            """]
        )
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertTrue(row.liveMarks.isEmpty, "незакрытая попытка уже нарисована в контуре")
        XCTAssertEqual(row.lanes[0].contours[0].segments.count, 1)
    }

    /// «Идёт сейчас» без записи о попытке — отдельный брусок.
    func testActiveSlotWithoutAttemptBecomesLiveMark() throws {
        let json = payload(
            attempts: [],
            active: ["""
            {"id":"s1","task_id":"t1","task_title":"Задача","task_created_at":"2026-10-12 10:10:00",
             "role_key":"builder","started_at":"2026-10-21T11:00:00.000Z","heartbeat_at":"2026-10-21T11:50:00.000Z"}
            """]
        )
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertEqual(row.liveMarks.count, 1)
        XCTAssertEqual(row.liveMarks[0].number, "МАК-1210-1310")
        XCTAssertEqual(row.liveMarks[0].origin, .liveMark)
    }

    /// Работа роли в чате без карточки — свой контур с названием работы.
    func testChatTurnBecomesChatContourWithWorkTitle() throws {
        let json = payload(
            attempts: [],
            chat: [chatTurn(id: "q1", title: "Экран загрузки ролей готов",
                            from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T09:30:00.000Z")]
        )
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertEqual(row.chatLanes.count, 1)
        let contour = try XCTUnwrap(row.chatLanes[0].first)
        XCTAssertEqual(contour.title, "Экран загрузки ролей готов")
        XCTAssertEqual(contour.chatTitle, "Чат про TaskFlow")
        XCTAssertEqual(contour.segments.count, 1)
    }

    /// Два хода в одном чате рядом — один контур; второй чат — другой.
    func testNearbyTurnsInSameChatMergeIntoOneContour() throws {
        let json = payload(
            attempts: [],
            chat: [
                chatTurn(id: "q1", title: "Первая работа",
                         from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T09:10:00.000Z"),
                chatTurn(id: "q2", title: "Вторая работа",
                         from: "2026-10-21T09:15:00.000Z", to: "2026-10-21T09:25:00.000Z"),
            ]
        )
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertEqual(row.chatLanes.count, 1, "ходы рядом в одном чате — один контур")
        XCTAssertEqual(row.chatLanes[0].count, 1)
        XCTAssertEqual(row.chatLanes[0][0].segments.count, 2)
    }

    /// Без карточной работы чатовые дорожки — единственные в роли.
    func testChatLanesDoNotDisturbCardLanes() throws {
        let json = payload(
            attempts: [attempt(id: "a1", task: "t1", from: "2026-10-21T08:00:00.000Z", to: "2026-10-21T08:30:00.000Z")],
            chat: [chatTurn(id: "q1", title: "Работа в чате",
                            from: "2026-10-21T09:00:00.000Z", to: "2026-10-21T09:30:00.000Z")]
        )
        let layout = RoleLoadLayout.build(try model(json), width: 1000)
        let row = try XCTUnwrap(layout.first)
        XCTAssertEqual(row.lanes.count, 1)
        XCTAssertEqual(row.lanes[0].contours.count, 1)
        XCTAssertEqual(row.chatLanes.count, 1)
    }
}
