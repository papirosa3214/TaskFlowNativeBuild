import Foundation

/// Единственный владелец «дня срока» в клиенте TaskFlow.
///
/// Срок задачи — **календарный день**, а не момент времени: на проводе это
/// строка `YYYY-MM-DD` без времени (spec/API.md §1), «сегодня» на сервере
/// считается по `Europe/Moscow` (сервер: `TASKFLOW_TIMEZONE`; клиент:
/// spec/SCREENS-1.md §4.1). Клиент хранит срок как `Date` — то есть как
/// момент времени, — поэтому значение приходится переводить между зонами:
/// зона устройства (системный пикер отдаёт дату в своей зоне) и зона задачи
/// (Москва). Пока перевод делался в разных местах и по-разному, день,
/// который пользователь видел в пикере, не совпадал с днём, который уходил
/// на сервер: на телефонах восточнее Москвы дата уезжала на сутки назад,
/// а на западных пикер показывал соседний день.
///
/// Правило одно: **срок хранится полночью дня в зоне задачи**, а пикер
/// показывает тот же календарный день, пересобирая его в своей зоне.
/// Все функции принимают зону параметром — иначе их нельзя проверить без
/// смены часового пояса телефона.
public enum TaskDay {

    /// Зона задачи: «сегодня» считается по Москве (spec/SCREENS-1.md §4.1).
    public static let moscow: TimeZone = TimeZone(identifier: "Europe/Moscow")
        ?? TimeZone(secondsFromGMT: 10_800)!

    /// Григорианский календарь в заданной зоне.
    public static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// Полночь дня в заданной зоне.
    public static func startOfDay(_ date: Date, timeZone zone: TimeZone = TaskDay.moscow) -> Date {
        calendar(zone).startOfDay(for: date)
    }

    /// `Date` → `YYYY-MM-DD` по заданной зоне.
    ///
    /// Считается вручную, без `DateFormatter`: строка срока собирается при
    /// каждом сохранении и при пересчёте «сегодня», а создание форматтера
    /// стоит десятки микросекунд (замерено 22.10.2026 на `DateFormatter`).
    public static func string(from date: Date, timeZone zone: TimeZone = TaskDay.moscow) -> String {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return pad(parts.year ?? 1970, 4) + "-" + pad(parts.month ?? 1, 2) + "-" + pad(parts.day ?? 1, 2)
    }

    /// `YYYY-MM-DD` → полночь этого дня в заданной зоне.
    ///
    /// Строка с сервера — календарная метка, а не момент времени: разбирать
    /// её надо в зоне ЗАДАЧИ (Москва), иначе в пикере на западных зонах
    /// показывался соседний день. Несуществующая дата (`2026-02-30`) → `nil`.
    public static func date(from raw: String?, timeZone zone: TimeZone = TaskDay.moscow) -> Date? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let cal = calendar(zone)
        guard let date = cal.date(from: DateComponents(timeZone: zone, year: year, month: month, day: day)) else {
            return nil
        }
        // Календарь по умолчанию «мягкий»: 30 февраля может превратиться в
        // 1 марта. Такое значение на проводе не встречается — но и принимать
        // его нельзя, иначе клиент молча поменяет день.
        let check = cal.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    /// «Сегодня» по зоне задачи — `YYYY-MM-DD`.
    public static func todayString(now: Date = Date(), timeZone zone: TimeZone = TaskDay.moscow) -> String {
        string(from: now, timeZone: zone)
    }

    /// Сдвиг на целое число дней по календарю зоны задачи.
    public static func addingDays(
        _ days: Int,
        to date: Date,
        timeZone zone: TimeZone = TaskDay.moscow
    ) -> Date {
        let cal = calendar(zone)
        return cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: date)) ?? date
    }

    /// День, выбранный в пикере, → полночь этого дня в зоне задачи.
    ///
    /// Системный `DatePicker` отдаёт дату в зоне устройства, и «день, который
    /// видит пользователь», — это календарные компоненты этой даты в зоне
    /// устройства. Берём именно их и собираем полночь того же дня в зоне
    /// задачи: так выбранный день доезжает до сервера тем же числом, что
    /// показал пикер.
    public static func instant(
        forPickerDay pickerDate: Date,
        deviceTimeZone: TimeZone = .autoupdatingCurrent,
        timeZone zone: TimeZone = TaskDay.moscow
    ) -> Date {
        let deviceParts = calendar(deviceTimeZone).dateComponents([.year, .month, .day], from: pickerDate)
        guard let year = deviceParts.year, let month = deviceParts.month, let day = deviceParts.day else {
            return startOfDay(pickerDate, timeZone: zone)
        }
        return calendar(zone).date(
            from: DateComponents(timeZone: zone, year: year, month: month, day: day)
        ) ?? startOfDay(pickerDate, timeZone: zone)
    }

    /// Значение срока (полночь в зоне задачи) → дата для пикера.
    ///
    /// Обратная операция к `instant(forPickerDay:)`: тот же календарный день,
    /// собранный полночью в зоне устройства. Без этого пикер на телефоне
    /// западнее Москвы показывал бы день, отличный от сохранённого.
    public static func pickerDate(
        forTaskDay value: Date,
        deviceTimeZone: TimeZone = .autoupdatingCurrent,
        timeZone zone: TimeZone = TaskDay.moscow
    ) -> Date {
        let taskParts = calendar(zone).dateComponents([.year, .month, .day], from: value)
        guard let year = taskParts.year, let month = taskParts.month, let day = taskParts.day else {
            return value
        }
        return calendar(deviceTimeZone).date(
            from: DateComponents(timeZone: deviceTimeZone, year: year, month: month, day: day)
        ) ?? value
    }

    /// Число с ведущими нулями: `7` → `07`, `2026` → `2026`.
    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        if text.count >= width { return text }
        return String(repeating: "0", count: width - text.count) + text
    }
}
