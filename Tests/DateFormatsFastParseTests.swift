import XCTest
@testable import TaskFlow

/// Быстрый разбор дат — LOCK-OPT-PERF-20261022.
///
/// `DateFormatter.date(from:)` на этой машине стоит 36-44 мкс на дату, а даты
/// разбираются сотни раз за кадр — в списках, в чате, в тепловой карте.
/// Ручной разбор канонического «yyyy-MM-dd HH:mm:ss» обязан давать РОВНО тот
/// же результат, что и форматтер, и отдавать неканоничные строки форматтеру.
final class DateFormatsFastParseTests: XCTestCase {

    /// Эталон — тот же форматтер, что внутри `DateFormats`.
    private let reference: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    func testБыстрыйРазборСовпадаетСФорматтером() {
        let samples = [
            "1970-01-01 00:00:00",
            "2026-10-22 12:00:00",
            "2026-10-22 00:00:00",
            "2026-10-22 23:59:59",
            "2026-01-01 00:00:01",
            "1999-06-15 08:30:45",
            "2024-02-29 23:59:59",
            "2000-02-29 12:00:00",
            "2026-12-31 23:59:59",
            "2026-03-01 00:00:00",
            "2026-10-31 12:00:00",
            "2026-11-30 12:00:00",
            "2100-03-01 00:00:00",
            "2001-09-09 01:46:40"
        ]
        for sample in samples {
            XCTAssertEqual(
                DateFormats.fastSQLiteUTC(sample),
                reference.date(from: sample),
                "Разбор разошёлся на «\(sample)»"
            )
        }
    }

    func testНеканоничныеСтрокиУходятВФорматтер() {
        // Быстрый путь такие строки отклоняет — и они уходят в форматтер.
        // Важно другое: форматтер умеет ПЕРЕНОСИТ лишние дни и часы
        // («2026-02-30» → 2 марта, «24:00:00» → следующий день), поэтому
        // проверяем не «nil», а равенство общей точки входа эталону.
        let rejected = [
            "2026-02-30 00:00:00",   // 30 февраля — форматтер переносит на 2 марта
            "2026-13-01 00:00:00",   // месяца нет
            "2026-00-10 00:00:00",   // месяц нулевой
            "2026-10-00 00:00:00",   // день нулевой
            "2026-10-22 24:00:00",   // час вне диапазона — переносится на следующий день
            "2026-10-22 12:60:00",   // минута вне диапазона
            "2026-10-22 12:00:60",   // секунда вне диапазона
            "2026-10-22 12:00",      // без секунд
            "2026-10-22",
            "не дата",
            ""
        ]
        for raw in rejected {
            XCTAssertNil(DateFormats.fastSQLiteUTC(raw), "«\(raw)» не должен проходить быстрым путём")
            XCTAssertEqual(
                DateFormats.sqliteUTC(raw),
                reference.date(from: raw),
                "Результат через общую точку входа разошёлся на «\(raw)»"
            )
        }
    }

    func testЧерезОбщуюТочкуВходаРезультатТотже() {
        for raw in ["2026-10-22 12:00:00", "2024-02-29 23:59:59", "1970-01-01 00:00:00"] {
            XCTAssertEqual(DateFormats.sqliteUTC(raw), reference.date(from: raw))
        }
        XCTAssertNil(DateFormats.sqliteUTC(""))
        XCTAssertNil(DateFormats.sqliteUTC(nil))
    }

    func testРазборСтрокиСервераНеСломался() {
        // `last_seen_at` приходит в ISO8601 — он и раньше шёл запасным путём.
        let iso = "2026-08-31T16:22:53.438Z"
        XCTAssertEqual(DateFormats.sqliteUTC(iso), DateFormats.iso8601(iso))
        XCTAssertNotNil(DateFormats.sqliteUTC(iso))
    }

    func testРучнойРазборЗаметноБыстрееФорматтера() {
        let samples = (0..<200).map { index in
            String(format: "2026-10-%02d %02d:%02d:%02d", index % 28 + 1, index % 24, index % 60, index % 60)
        }
        let slowStart = DispatchTime.now().uptimeNanoseconds
        for sample in samples { _ = reference.date(from: sample) }
        let slow = Double(DispatchTime.now().uptimeNanoseconds - slowStart)

        let fastStart = DispatchTime.now().uptimeNanoseconds
        for sample in samples { _ = DateFormats.fastSQLiteUTC(sample) }
        let fast = Double(DispatchTime.now().uptimeNanoseconds - fastStart)

        XCTAssertLessThan(fast, slow / 5, "Ручной разбор должен быть в разы быстрее форматтера")
    }
}
