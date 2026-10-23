import XCTest
@testable import TaskFlow

/// Форматирование рутин: подпись правила, «следующий запуск» в зоне самой
/// рутины, дни недели, интервал.
final class RoutineFormatTests: XCTestCase {

    private func makeSchedule(
        ruleKind: String = "weekdays",
        ruleExpr: String? = nil,
        ruleLabel: String? = "По будням",
        timeLocal: String = "09:00",
        timezone: String = "Europe/Moscow",
        nextRunAt: String? = nil,
        status: String = "active"
    ) -> ApiSchedule {
        let json = """
        {
          "id": "sch-1",
          "title": "Отчёт продаж",
          "task_payload": { "title": "Отчёт продаж" },
          "rule_kind": "\(ruleKind)",
          "rule_expr": \(ruleExpr.map { "\"\($0)\"" } ?? "null"),
          "rule_label": \(ruleLabel.map { "\"\($0)\"" } ?? "null"),
          "time_local": "\(timeLocal)",
          "timezone": "\(timezone)",
          "next_run_at": \(nextRunAt.map { "\"\($0)\"" } ?? "null"),
          "last_run_at": null,
          "status": "\(status)",
          "catch_up": true,
          "overlap_policy": "skip",
          "current_task_id": null,
          "created_at": "2026-10-22T06:00:00.000Z",
          "updated_at": "2026-10-22T06:00:00.000Z"
        }
        """
        return try! JSONDecoder().decode(ApiSchedule.self, from: Data(json.utf8))
    }

    /// Подпись правила берётся с сервера — веб и iOS показывают одно и то же.
    func testServerRuleLabelWins() {
        let schedule = makeSchedule(ruleLabel: "По будням")
        XCTAssertEqual(RoutineFormat.ruleLabel(for: schedule), "По будням")
    }

    /// На сервере старше этой правки подписи нет — тогда клиент не молчит,
    /// а собирает свою из правила и дней недели.
    func testFallbackRuleLabelForWeekdays() {
        let schedule = makeSchedule(ruleKind: "weekly_days", ruleExpr: "1,3,5", ruleLabel: nil)
        XCTAssertEqual(RoutineFormat.ruleLabel(for: schedule), "Пн, Ср, Пт")
    }

    func testFallbackRuleLabelForInterval() {
        let schedule = makeSchedule(ruleKind: "interval", ruleExpr: "15m", ruleLabel: nil)
        XCTAssertEqual(RoutineFormat.ruleLabel(for: schedule), "Каждые 15 минут")
    }

    /// «Следующий запуск» считается в зоне рутины, а не в зоне телефона.
    func testNextRunLabelUsesRoutineTimezone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 0))!
        // Завтра, 09:00 по Москве = 2026-10-23T06:00:00Z
        let label = RoutineFormat.nextRunLabel(nextRunAt: "2026-10-23T06:00:00.000Z", timezone: "Europe/Moscow", now: now)
        XCTAssertEqual(label, "завтра, 09:00")
    }

    /// Тот же момент в зоне телефона — «сегодня»: разница только в зоне.
    func testNextRunLabelToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 8, minute: 0))!
        let label = RoutineFormat.nextRunLabel(nextRunAt: "2026-10-22T09:00:00.000Z", timezone: "Europe/Moscow", now: now)
        XCTAssertEqual(label, "сегодня, 12:00")
    }

    func testNextRunLabelForFarDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 0))!
        let label = RoutineFormat.nextRunLabel(nextRunAt: "2026-10-25T06:00:00.000Z", timezone: "Europe/Moscow", now: now)
        XCTAssertEqual(label, "25.10, 09:00")
    }

    func testIntervalExpression() {
        XCTAssertEqual(RoutineFormat.intervalExpr(minutes: 15), "15m")
        XCTAssertEqual(RoutineFormat.intervalExpr(minutes: 120), "2h")
        // Минимум планировщика — 5 минут: меньше нельзя.
        XCTAssertEqual(RoutineFormat.intervalExpr(minutes: 1), "5m")
        XCTAssertEqual(RoutineFormat.intervalMinutes("2h"), 120)
        XCTAssertEqual(RoutineFormat.intervalMinutes("15m"), 15)
        XCTAssertNil(RoutineFormat.intervalMinutes("abc"))
    }

    func testWeekdaysExpressionAndParsing() {
        XCTAssertEqual(RoutineFormat.weekdaysExpr([5, 1, 3]), "1,3,5")
        XCTAssertEqual(RoutineFormat.parseWeekdays("1,3,5"), [1, 3, 5])
        XCTAssertNil(RoutineFormat.parseWeekdays("1,9"))
        XCTAssertNil(RoutineFormat.parseWeekdays(""))
    }

    func testTimeLocalConversion() {
        XCTAssertEqual(RoutineFormat.timeLocalText(9 * 60), "09:00")
        XCTAssertEqual(RoutineFormat.minutesFromTimeLocal("09:30"), 570)
        // Час — одна или две цифры (как на сервере), минуты — ровно две.
        XCTAssertEqual(RoutineFormat.minutesFromTimeLocal("9:30"), 570)
        XCTAssertNil(RoutineFormat.minutesFromTimeLocal("9:3"))
        XCTAssertNil(RoutineFormat.minutesFromTimeLocal("24:00"))
        XCTAssertNil(RoutineFormat.minutesFromTimeLocal("09:60"))
    }

    /// «Еженедельно» и «Ежемесячно» без серверной подписи собираются так же,
    /// как на сервере, — иначе подписи веба и iOS разойдутся.
    func testFallbackRuleLabelForWeeklyAndMonthly() {
        XCTAssertEqual(RoutineFormat.fallbackRuleLabel(kind: "weekly", expr: "3"), "Еженедельно: среда")
        XCTAssertEqual(RoutineFormat.fallbackRuleLabel(kind: "weekly", expr: "7"), "Еженедельно: воскресенье")
        XCTAssertEqual(RoutineFormat.fallbackRuleLabel(kind: "monthly", expr: "15"), "Ежемесячно: 15-е число")
        XCTAssertEqual(RoutineFormat.fallbackRuleLabel(kind: "weekly", expr: nil), "Еженедельно")
    }

    /// Правило «Еженедельно» без дня недели — сервер берёт день из якоря, но
    /// клиент подставляет сегодняшний: так подпись и запуск совпадают.
    func testWeeklyAndMonthlyExpressions() {
        XCTAssertEqual(RoutineFormat.weekdayExpr(3), "3")
        XCTAssertEqual(RoutineFormat.weekdayExpr(9), "7")
        XCTAssertEqual(RoutineFormat.monthDayExpr(15), "15")
        XCTAssertEqual(RoutineFormat.monthDayExpr(0), "1")
        XCTAssertEqual(RoutineFormat.monthDayExpr(40), "31")
    }

    /// Сегодняшний день недели в зоне рутины: 1 = понедельник (как у сервера),
    /// 7 = воскресенье.
    func testTodayWeekdayUsesRoutineTimezone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        XCTAssertEqual(RoutineFormat.todayWeekday(timezone: "Europe/Moscow", now: now), 4)
        XCTAssertEqual(RoutineFormat.todayMonthDay(timezone: "Europe/Moscow", now: now), 22)
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        XCTAssertEqual(RoutineFormat.todayWeekday(timezone: "Europe/Moscow", now: sunday), 7)
    }

    /// Тост запуска показывает причину, которую дал сервер.
    func testRunNoticeKeepsServerReason() {
        XCTAssertEqual(RoutineFormat.runNotice(status: "created", detail: "карточка создана"), "Задача создана")
        XCTAssertEqual(
            RoutineFormat.runNotice(status: "skipped", detail: "прошлый экземпляр не закрыт"),
            "Пропущено: прошлый экземпляр не закрыт"
        )
        XCTAssertEqual(RoutineFormat.runNotice(status: "skipped", detail: nil), "Пропущено")
    }

    func testRunStatusTitles() {
        XCTAssertEqual(RoutineFormat.runStatusTitle("created"), "Задача создана")
        XCTAssertEqual(RoutineFormat.runStatusTitle("skipped"), "Пропущено")
        XCTAssertEqual(RoutineFormat.runStatusTitle("error"), "Ошибка")
    }
}
