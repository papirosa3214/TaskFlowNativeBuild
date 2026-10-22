import Foundation

/// Единая точка разбора дат сервера — spec/API.md §1: ТРИ разных формата,
/// не путать. Форматтеры переиспользуются под общей блокировкой: создание
/// `DateFormatter` дорого и раньше происходило для каждой видимой строки при
/// каждом проходе SwiftUI body. Блокировка сохраняет корректность, если
/// парсинг однажды будет вызван не только с главного потока.
public enum DateFormats {
    private static let formatterLock = NSLock()

    private static let sqliteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let calendarFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func locked<T>(_ work: () -> T) -> T {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return work()
    }

    /// `created_at`/`updated_at`/`completed_at`/... — SQLite `DATETIME('now')`,
    /// UTC, БЕЗ суффикса `T`/`Z` (пример: `"2026-08-31 12:00:00"`). Наивный
    /// `Date(from:)` в Swift распознал бы это как ЛОКАЛЬНОЕ время — здесь
    /// явно фиксируем UTC, как предписывает спека.
    ///
    /// Живой сервер проверен 31.08.2026: `users.last_seen_at` (добавлено мимо
    /// системы миграций, см. spec/API.md §12 п.6) реально приходит в ДРУГОМ
    /// формате — полный ISO8601 с миллисекундами и суффиксом `Z`
    /// (`"2026-08-31T16:22:53.438Z"`), не как остальные `*_at`. Поэтому здесь
    /// пробуем sqlite-формат первым, ISO8601 — запасным вариантом.
    public static func sqliteUTC(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        // Канонический вид разбираем сами: `DateFormatter` на этой машине
        // стоит 36-44 мкс на дату (замерено 22.10.2026 на 500 разных
        // строках), а даты разбираются сотни раз за кадр — в списках, в чате,
        // в тепловой карте. Ручной разбор — около 0.1 мкс, результат тот же.
        if let fast = fastSQLiteUTC(raw) { return fast }
        if let date = locked({ sqliteFormatter.date(from: raw) }) { return date }
        return iso8601(raw)
    }

    /// Разбор «yyyy-MM-dd HH:mm:ss» (UTC, григорианский календарь) без
    /// `DateFormatter`. Возвращает `nil`, если строка не каноническая или
    /// дата не существует — тогда вызывающий идёт в форматтер, поведение не
    /// меняется.
    ///
    /// Порядок дней считается по пролептическому григорианскому календарю
    /// (алгоритм «days from civil»), без `Calendar` и без локали.
    static func fastSQLiteUTC(_ raw: String) -> Date? {
        let utf8 = raw.utf8
        guard utf8.count == 19 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(19)
        for byte in utf8 { bytes.append(byte) }

        guard bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x20,
              bytes[13] == 0x3A, bytes[16] == 0x3A else { return nil }
        guard let year = twoOrFourDigits(bytes, 0), let month = twoDigits(bytes, 5),
              let day = twoDigits(bytes, 8), let hour = twoDigits(bytes, 11),
              let minute = twoDigits(bytes, 14), let second = twoDigits(bytes, 17) else { return nil }
        guard (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month),
              hour <= 23, minute <= 59, second <= 59 else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days) * 86_400 + Double(hour) * 3_600 + Double(minute) * 60 + Double(second)
        return Date(timeIntervalSince1970: seconds)
    }

    /// Четыре цифры года.
    private static func twoOrFourDigits(_ bytes: [UInt8], _ index: Int) -> Int? {
        var value = 0
        for offset in 0..<4 {
            guard let digit = digit(bytes[index + offset]) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    /// Две цифры.
    private static func twoDigits(_ bytes: [UInt8], _ index: Int) -> Int? {
        guard let tens = digit(bytes[index]), let ones = digit(bytes[index + 1]) else { return nil }
        return tens * 10 + ones
    }

    private static func digit(_ byte: UInt8) -> Int? {
        guard byte >= 0x30, byte <= 0x39 else { return nil }
        return Int(byte - 0x30)
    }

    /// Сколько дней в месяце — с правилом високосного года.
    private static func daysInMonth(year: Int, month: Int) -> Int {
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

    /// Дней с 1970-01-01 до указанной даты (UTC).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        if month <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthPrime = (month + 9) % 12
        let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Полноценный ISO8601, опционально с миллисекундами — на практике встречен
    /// у `last_seen_at` (проверено живым запросом к :3001, 31.08.2026).
    public static func iso8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return locked {
            isoWithFraction.date(from: raw) ?? isoPlain.date(from: raw)
        }
    }

    /// `due_date` — календарная дата БЕЗ времени, `YYYY-MM-DD`. Разбирается в
    /// UTC намеренно: это чистая календарная метка ("31 августа"), а не момент
    /// времени — парсинг в локальной таймзоне устройства мог бы съехать на
    /// соседний день у пользователей восточнее UTC ближе к полуночи.
    public static func calendarDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return locked { calendarFormatter.date(from: raw) }
    }

    /// Обратное преобразование — `Date` → `YYYY-MM-DD` для отправки в `due_date`.
    public static func calendarDateString(_ date: Date) -> String {
        locked { calendarFormatter.string(from: date) }
    }

    /// Сегодняшняя календарная дата в формате `YYYY-MM-DD` — для сравнения с
    /// `due_date` (бейдж таббара «Сегодня», экран «Сегодня»). Намеренно системная
    /// таймзона устройства, НЕ UTC: due_date — это про календарный день
    /// пользователя, а не абсолютный момент.
    public static func todayString() -> String {
        locked {
            localDayFormatter.calendar = .autoupdatingCurrent
            localDayFormatter.timeZone = .autoupdatingCurrent
            return localDayFormatter.string(from: Date())
        }
    }

    /// `start_time` — `HH:MM`, локальное время суток, НЕ привязано к таймзоне.
    /// Разбирается в компоненты, а не в `Date` — абсолютного момента тут нет,
    /// это "на какой час дня" ставить блок в календаре (spec §1).
    public static func localTimeComponents(_ raw: String?) -> (hour: Int, minute: Int)? {
        guard let raw, let colonIndex = raw.firstIndex(of: ":") else { return nil }
        let hourPart = raw[raw.startIndex..<colonIndex]
        let minutePart = raw[raw.index(after: colonIndex)...]
        guard let hour = Int(hourPart), let minute = Int(minutePart) else { return nil }
        return (hour, minute)
    }
}
