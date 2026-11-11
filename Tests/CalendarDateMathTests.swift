import XCTest
@testable import TaskFlow

/// Календарная арифметика без `DateFormatter` — LOCK-OPT-PERF-20261024.
///
/// Продолжение `LOCK-OPT-PERF-20261022`: быстрый разбор дат тогда добавили в
/// `DateFormats.sqliteUTC`, но четыре экранных копии разбора
/// (`TodayDate`, `UpcomingDate`, `DirectoryDate`, `TaskDateText`) создавали
/// `DateFormatter` НА КАЖДЫЙ вызов — замер 24.10.2026: 162.5 мкс на создание
/// форматтера + разбор против 0.05 мкс ручного разбора.
///
/// Тест проверяет ровно одно: результат совпадает с эталонным форматтером
/// (григорианский календарь, UTC, POSIX-локаль) — и что экранные хелперы,
/// которые зовут этот разбор, больше не создают форматтер на каждый вызов.
final class CalendarDateMathTests: XCTestCase {

    /// Эталон — тот же форматтер, что внутри `DateFormats`.
    private let reference: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Совпадение с эталоном

    func testРазборСовпадаетСФорматтером() {
        let samples = [
            "1970-01-01", "2000-02-29", "2024-02-29", "2026-10-24",
            "2026-01-01", "2026-12-31", "1999-06-15", "2100-03-01",
            "2026-08-31", "2026-10-22"
        ]
        for sample in samples {
            XCTAssertEqual(
                CalendarDateMath.calendarDate(sample),
                reference.date(from: sample),
                "Разбор разошёлся на «\(sample)»"
            )
        }
    }

    func testНеканоничныеСтрокиВедутСебяКакУФорматтера() {
        // Каноничный вид разбирается руками, остальное уходит в форматтер —
        // поэтому поведение совпадает с эталоном в точности, включая переносы
        // «2026-02-30» → 2 марта и отказы на мусорных строках.
        let samples = [
            "2026-02-30", "2026-13-01", "2026-00-10", "2026-10-00",
            "2026-1-1", "2026-10-24T00:00:00Z", "24.10.2026", "не дата", ""
        ]
        for sample in samples {
            XCTAssertEqual(
                CalendarDateMath.calendarDate(sample),
                reference.date(from: sample),
                "Поведение разошлось с форматтером на «\(sample)»"
            )
        }
        XCTAssertNil(CalendarDateMath.calendarDate(nil))
        XCTAssertNil(CalendarDateMath.calendarDate(""))
    }

    func testОбратноеПреобразованиеСовпадаетСФорматтером() {
        let samples = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: -86_400),          // 1969-12-31
            Date(timeIntervalSince1970: -1_000_000_000),
            Date(timeIntervalSince1970: 1_767_225_600),   // 2026-01-01
            Date(timeIntervalSince1970: 4_102_444_800)    // 2100-01-01
        ]
        for sample in samples {
            XCTAssertEqual(
                CalendarDateMath.calendarDateString(sample),
                reference.string(from: sample),
                "Форматирование разошлось на \(sample)"
            )
        }
    }

    func testДеньНеделиСовпадаетСКалендарём() {
        // 0 — воскресенье, как `Calendar.component(.weekday) - 1`.
        var date = utcCalendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        for _ in 0..<20_000 {
            let raw = reference.string(from: date)
            let expected = utcCalendar.component(.weekday, from: date) - 1
            XCTAssertEqual(CalendarDateMath.weekdayIndex(raw), expected, "День недели разошёлся на «\(raw)»")
            date = utcCalendar.date(byAdding: .day, value: 1, to: date)!
        }
    }

    func testДобавлениеДнейСовпадаетСКалендарём() {
        let samples = ["2026-10-24", "2026-01-31", "2026-02-28", "2024-02-28", "2026-12-31", "1970-01-01"]
        for sample in samples {
            let base = reference.date(from: sample)!
            for shift in [-400, -31, -7, -1, 0, 1, 7, 31, 365, 400] {
                let expected = utcCalendar.date(byAdding: .day, value: shift, to: base)!
                XCTAssertEqual(
                    CalendarDateMath.addingDays(sample, shift),
                    reference.string(from: expected),
                    "Сдвиг на \(shift) дней разошёлся на «\(sample)»"
                )
            }
        }
    }

    /// Месячная сетка планирования — 42 даты с понедельника недели первого
    /// числа. Сверяем с эталонным `Calendar`-алгоритмом, который был в коде
    /// до перехода на ручную арифметику.
    func testМесячнаяСеткаСовпадаетСКалендарём() {
        for year in [2024, 2025, 2026, 2027] {
            for month in 0..<12 {
                let grid = UpcomingDate.monthGridDates(year: year, month: month)
                XCTAssertEqual(grid.count, 42, "Сетка \(year)-\(month + 1) собралась не из 42 дат")
                var comps = DateComponents()
                comps.year = year
                comps.month = month + 1
                comps.day = 1
                guard let first = utcCalendar.date(from: comps) else { continue }
                let weekday = utcCalendar.component(.weekday, from: first) - 1 // 0=вс
                let lead = weekday == 0 ? 6 : weekday - 1
                guard let start = utcCalendar.date(byAdding: .day, value: -lead, to: first) else { continue }
                for (index, value) in grid.enumerated() {
                    let expected = utcCalendar.date(byAdding: .day, value: index, to: start)!
                    XCTAssertEqual(value, reference.string(from: expected),
                                   "Сетка \(year)-\(month + 1) разошлась на ячейке \(index)")
                }
            }
        }
    }

    func testСоставныеЧастиСовпадаютСКалендарём() {
        for raw in ["2026-10-24", "2026-01-01", "2024-02-29", "1999-12-31"] {
            let date = reference.date(from: raw)!
            let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
            let fast = CalendarDateMath.components(raw)
            XCTAssertEqual(fast?.year, comps.year)
            XCTAssertEqual(fast?.month, comps.month)
            XCTAssertEqual(fast?.day, comps.day)
        }
    }

    // MARK: - Производительность

    func testЭкранныеХелперыНеСоздаютФорматтерНаКаждыйВызов() {
        // Эталон — ОДИН разбор кэшированным форматтером.
        let samples = (0..<200).map { index in
            String(format: "2026-%02d-%02d", index % 12 + 1, index % 28 + 1)
        }
        let referenceStart = DispatchTime.now().uptimeNanoseconds
        for sample in samples { _ = reference.date(from: sample) }
        let referenceElapsed = Double(DispatchTime.now().uptimeNanoseconds - referenceStart) / Double(samples.count)

        // Тот же объём через экранный хелпер: он зовёт разбор даты и считает
        // подпись. Раньше на каждый вывод создавался `DateFormatter`.
        let helperStart = DispatchTime.now().uptimeNanoseconds
        for sample in samples { _ = DirectoryDate.formatDueLabel(sample) }
        let helperElapsed = Double(DispatchTime.now().uptimeNanoseconds - helperStart) / Double(samples.count)

        print("ЗАМЕР календарных дат: эталонный разбор \(String(format: "%.2f", referenceElapsed / 1000)) мкс, экранный хелпер \(String(format: "%.2f", helperElapsed / 1000)) мкс")
        XCTAssertLessThan(
            helperElapsed,
            referenceElapsed / 2,
            "Экранный хелпер всё ещё создаёт DateFormatter на каждый вызов"
        )
    }

    func testСдвигДатыВПланированииНеСоздаётФорматтерНаКаждыйВызов() {
        // `UpcomingDate.addDays` зовётся десятками раз на 42 ячейки месячной
        // сетки — каждый вызов раньше создавал два `DateFormatter`.
        let iterations = 200
        let referenceStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations { _ = reference.date(from: "2026-10-24") }
        let referenceElapsed = Double(DispatchTime.now().uptimeNanoseconds - referenceStart) / Double(iterations)

        let helperStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations { _ = UpcomingDate.addDays("2026-10-24", index % 7) }
        let helperElapsed = Double(DispatchTime.now().uptimeNanoseconds - helperStart) / Double(iterations)

        print("ЗАМЕР сдвига даты: эталонный разбор \(String(format: "%.2f", referenceElapsed / 1000)) мкс, addDays \(String(format: "%.2f", helperElapsed / 1000)) мкс")
        XCTAssertLessThan(
            helperElapsed,
            referenceElapsed / 2,
            "`UpcomingDate.addDays` всё ещё создаёт DateFormatter на каждый вызов"
        )
    }

    // MARK: - Поведение экранов не изменилось

    func testПодписиЭкрановНеИзменились() {
        XCTAssertEqual(UpcomingDate.jsWeekday("2026-10-24"), 6)
        XCTAssertEqual(UpcomingDate.day("2026-10-24"), 24)
        XCTAssertEqual(UpcomingDate.yearMonth("2026-10-24").year, 2026)
        XCTAssertEqual(UpcomingDate.yearMonth("2026-10-24").month, 9)
        XCTAssertEqual(UpcomingDate.addDays("2026-10-24", 8), "2026-11-01")
        XCTAssertEqual(UpcomingDate.mondayOf("2026-10-24"), "2026-10-19")
    }
}
