import Foundation

/// Календарная арифметика без `DateFormatter` и `Calendar` в горячих путях.
///
/// Замер 24.10.2026 на этой машине (500 разных строк):
/// - `DateFormatter` создаётся на каждый вызов + разбор — **162.5 мкс**;
/// - кэшированный форматтер, только разбор — **37 мкс**;
/// - ручной разбор — **0.05 мкс**.
///
/// Даты разбираются сотнями за один проход `body`: в списке задач («срок»,
/// «осталось N дней»), в месячной сетке планирования (`addDays` вызывается
/// десятками раз на 42 ячейки), в шапке «Сегодня». Экранные хелперы
/// (`TodayDate`, `UpcomingDate`, `DirectoryDate`, `TaskDateText`) держали свои
/// копии этого разбора и создавали форматтер на каждый вызов — четыре копии
/// одного и того же дефекта.
///
/// Поведение не меняется: канонический «yyyy-MM-DD» разбирается вручную, а
/// всё неканоничное (в том числе даты, которые `DateFormatter` переносит сам —
/// «2026-02-30» → 2 марта) уходит в форматтер, как и раньше.
public enum CalendarDateMath {

    // MARK: - Разбор

    /// `YYYY-MM-DD` → полночь UTC (чистая календарная метка, без сдвига по
    /// таймзоне устройства). Год/месяц/день считаются по пролептическому
    /// григорианскому календарю (алгоритм «days from civil»).
    public static func calendarDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let fast = fastCalendarDate(raw) { return fast }
        return fallbackFormatter.date(from: raw)
    }

    /// Ручной разбор канонической даты. `nil`, если строка не каноническая или
    /// дата не существует — тогда вызывающий идёт в форматтер.
    static func fastCalendarDate(_ raw: String) -> Date? {
        if let date = raw.utf8.withContiguousStorageIfAvailable({ fastCalendarDate(bytes: $0) }) {
            return date
        }
        // Редкий случай: строка не нативная (например, из Objective-C).
        var copy = [UInt8]()
        copy.reserveCapacity(10)
        copy.append(contentsOf: raw.utf8)
        return copy.withUnsafeBufferPointer { fastCalendarDate(bytes: $0) }
    }

    private static func fastCalendarDate(bytes: UnsafeBufferPointer<UInt8>) -> Date? {
        guard bytes.count == 10 else { return nil }
        guard bytes[4] == 0x2D, bytes[7] == 0x2D else { return nil }
        guard let year = fourDigits(bytes, 0), let month = twoDigits(bytes, 5),
              let day = twoDigits(bytes, 8) else { return nil }
        guard (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month) else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        return Date(timeIntervalSince1970: Double(days) * 86_400)
    }

    /// Год, месяц (1...12), день — из канонической даты.
    public static func components(_ raw: String) -> (year: Int, month: Int, day: Int)? {
        guard let date = calendarDate(raw) else { return nil }
        let days = Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
        let civil = civilFromDays(days)
        return (civil.year, civil.month, civil.day)
    }

    /// День недели: 0 — воскресенье (как `Calendar.component(.weekday) - 1`
    /// и как `Date.getDay()` в вебе). 1970-01-01 — четверг, поэтому смещение 4.
    public static func weekdayIndex(_ raw: String) -> Int? {
        guard let date = calendarDate(raw) else { return nil }
        let days = Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
        return (days + 4 + 7) % 7
    }

    /// Календарная дата + N дней — тоже без форматтера.
    public static func addingDays(_ raw: String, _ days: Int) -> String? {
        guard let date = calendarDate(raw) else { return nil }
        let base = Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
        let shifted = base + days
        let civil = civilFromDays(shifted)
        return format(civil.year, civil.month, civil.day)
    }

    // MARK: - Форматирование

    /// `Date` → `YYYY-MM-DD` в UTC.
    public static func calendarDateString(_ date: Date) -> String {
        let days = Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
        let civil = civilFromDays(days)
        return format(civil.year, civil.month, civil.day)
    }

    /// `YYYY-MM-DD` в заданной таймзоне — для дат, которые живут по
    /// московскому времени, а не по UTC.
    public static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        let seconds = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        let days = Int((seconds / 86_400).rounded(.down))
        let civil = civilFromDays(days)
        return format(civil.year, civil.month, civil.day)
    }

    private static func format(_ year: Int, _ month: Int, _ day: Int) -> String {
        var out = String(year)
        while out.count < 4 { out = "0" + out }
        var result = out
        result += month < 10 ? "-0\(month)" : "-\(month)"
        result += day < 10 ? "-0\(day)" : "-\(day)"
        return result
    }

    // MARK: - Эталонный форматтер

    /// Тот же форматтер, что и в `DateFormats`: григорианский календарь, UTC,
    /// POSIX-локаль. Кэшируется — создание `DateFormatter` стоит 162 мкс.
    private static let fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Арифметика дней

    private static func fourDigits(_ bytes: UnsafeBufferPointer<UInt8>, _ index: Int) -> Int? {
        var value = 0
        for offset in 0..<4 {
            guard let digit = digit(bytes[index + offset]) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    private static func twoDigits(_ bytes: UnsafeBufferPointer<UInt8>, _ index: Int) -> Int? {
        guard let tens = digit(bytes[index]), let ones = digit(bytes[index + 1]) else { return nil }
        return tens * 10 + ones
    }

    private static func digit(_ byte: UInt8) -> Int? {
        guard byte >= 0x30, byte <= 0x39 else { return nil }
        return Int(byte - 0x30)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Дней с 1970-01-01 до указанной даты (пролептический григорианский).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        if month <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthPrime = (month + 9) % 12
        let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Обратное преобразование: дни с 1970-01-01 → (год, месяц, день).
    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        var z = days
        z += 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let y = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        return (month <= 2 ? y + 1 : y, month, day)
    }
}
