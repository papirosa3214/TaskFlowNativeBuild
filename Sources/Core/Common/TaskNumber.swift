import Foundation

/// Номер задачи для Ганта и карточки: «МАК-ДДММ-ЧЧММ».
///
/// Владелец 21.10.2026: «исходя из кода типа макс, дефис и цифры» и «две
/// карточки в одну секунду не создаются» — значит пара (день+месяц,
/// час+минута) различает задачи практически всегда. Год не пишем: он
/// добавляет символы в подпись, а различать карточки в пределах года
/// достаточно. Время считаем по МСК — тем же поясом, что и остальные
/// календарные подписи приложения (`TaskDateText`).
public enum TaskNumber {

    private static let moscow = TimeZone(identifier: "Europe/Moscow")!

    /// Номер по моменту создания. `nil`, если даты нет.
    public static func text(for date: Date?) -> String? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = moscow
        let parts = calendar.dateComponents([.day, .month, .hour, .minute], from: date)
        guard let day = parts.day, let month = parts.month,
              let hour = parts.hour, let minute = parts.minute else { return nil }
        return String(format: "МАК-%02d%02d-%02d%02d", day, month, hour, minute)
    }

    /// Номер по `created_at` задачи (UTC, формат SQLite).
    public static func text(forCreatedAt raw: String?) -> String? {
        text(for: DateFormats.sqliteUTC(raw))
    }
}
