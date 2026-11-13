import XCTest

/// Архив и статистика закрытых задач на телефоне (владелец 13.11.2026):
/// мини-карточки за 30 дней приходят дельтами, статистика — снимок с
/// сервера «в какой день сколько задач», убранное с телефона из статистики
/// не пропадает.
final class ClosedTasksFeedTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-13T12:00:00Z")!

    private func item(_ id: String, closedAt: String = "2026-11-12 10:00:00", outcome: String? = "Готово") -> ClosedTaskItem {
        ClosedTaskItem(id: id, title: "Задача \(id)", projectName: "Проект", kind: .completed,
                       closedAt: closedAt, outcome: outcome)
    }

    @objc func testFullReplacesAndDeltaUpserts() {
        var snapshot = ClosedTasksSnapshot()
        snapshot.apply(ClosedTasksResponse(serverTime: "c1", full: true, items: [item("a"), item("b")], removedIDs: []), now: now)
        XCTAssertEqual(snapshot.items.map(\.id), ["a", "b"])
        XCTAssertEqual(snapshot.closedCursor, "c1")

        var changedB = item("b")
        changedB.outcome = "Новый итог"
        snapshot.apply(ClosedTasksResponse(serverTime: "c2", full: false, items: [changedB, item("c")], removedIDs: ["a"]), now: now)
        XCTAssertEqual(Set(snapshot.items.map(\.id)), ["b", "c"])
        XCTAssertEqual(snapshot.items.first { $0.id == "b" }?.outcome, "Новый итог")
        XCTAssertEqual(snapshot.closedCursor, "c2")
    }

    @objc func testOlderThanMonthLeavesPhone() {
        var snapshot = ClosedTasksSnapshot()
        snapshot.apply(ClosedTasksResponse(serverTime: "c1", full: true,
                                           items: [item("fresh"), item("old", closedAt: "2026-10-01 10:00:00")],
                                           removedIDs: []), now: now)
        XCTAssertEqual(snapshot.items.map(\.id), ["fresh"])
    }

    @objc func testItemsSortedNewestFirst() {
        var snapshot = ClosedTasksSnapshot()
        snapshot.apply(ClosedTasksResponse(serverTime: "c1", full: true,
                                           items: [item("early", closedAt: "2026-11-10 10:00:00"),
                                                   item("late", closedAt: "2026-11-12 10:00:00")],
                                           removedIDs: []), now: now)
        XCTAssertEqual(snapshot.items.map(\.id), ["late", "early"])
    }

    @objc func testHiddenStaysOffPhoneButNotStats() {
        var snapshot = ClosedTasksSnapshot()
        snapshot.apply(DailyStatsResponse(serverTime: "1", full: true, days: [DailyCount(day: "2026-11-12", count: 2)]))
        snapshot.apply(ClosedTasksResponse(serverTime: "c1", full: true, items: [item("a")], removedIDs: []), now: now)
        snapshot.hide("a")
        XCTAssertTrue(snapshot.items.isEmpty)
        // Сервер прислал ту же карточку снова (правка) — на телефон не возвращается.
        snapshot.apply(ClosedTasksResponse(serverTime: "c2", full: false, items: [item("a")], removedIDs: []), now: now)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertEqual(snapshot.days["2026-11-12"], 2, "статистика не трогается")
    }

    @objc func testDailyDeltaUpdatesOnlyChangedDays() {
        var snapshot = ClosedTasksSnapshot()
        snapshot.apply(DailyStatsResponse(serverTime: "3", full: true,
                                          days: [DailyCount(day: "2026-11-11", count: 4), DailyCount(day: "2026-11-12", count: 2)]))
        snapshot.apply(DailyStatsResponse(serverTime: "4", full: false,
                                          days: [DailyCount(day: "2026-11-12", count: 3), DailyCount(day: "2026-11-11", count: 0)]))
        XCTAssertEqual(snapshot.days, ["2026-11-12": 3])
        XCTAssertEqual(snapshot.statsCursor, "4")
    }

    @objc func testDecodesServerShape() throws {
        let json = #"{"server_time":"2026-11-13 00:30:00","full":false,"items":[{"id":"x","title":"Т","project_name":null,"kind":"archived","closed_at":"2026-11-12 10:00:00","outcome":null}],"removed_ids":["y"]}"#
        let response = try JSONDecoder().decode(ClosedTasksResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.items.first?.kind, .archived)
        XCTAssertEqual(response.removedIDs, ["y"])
        let daily = try JSONDecoder().decode(DailyStatsResponse.self,
                                             from: Data(#"{"server_time":"7","full":true,"days":[{"day":"2026-11-12","count":5}]}"#.utf8))
        XCTAssertEqual(daily.days.first?.count, 5)
    }
}
