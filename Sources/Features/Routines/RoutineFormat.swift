import Foundation

// Форматирование рутин: подпись правила, «следующий запуск», дни недели,
// интервал. Отдельный файл без SwiftUI — чтобы это проверялось обычным
// модульным тестом (Tests/RoutineFormatTests.swift).
//
// Словарь — общий с вебом (дизайн, п. 2.3): рутина — это «рутина», а не
// «повтор» и не «расписание задачи».
public enum RoutineFormat {

    /// Минимальный интервал планировщика — 5 минут (спека, раздел 5).
    public static let minimumIntervalMinutes = 5
    public static let defaultTimezone = "Europe/Moscow"
    public static let defaultTime = "09:00"

    /// Правила, которые сервер принимает (`SCHEDULE_RULE_KINDS`).
    public static let ruleKinds = ["once", "daily", "weekdays", "weekly", "weekly_days", "monthly", "interval"]

    /// Название правила по-русски — только запасной вариант: обычно подпись
    /// приходит с сервера (`rule_label`), и веб и iOS показывают одно и то же.
    public static func ruleKindTitle(_ kind: String) -> String {
        switch kind {
        case "once": return "Однократно"
        case "daily": return "Ежедневно"
        case "weekdays": return "По будням"
        case "weekly": return "Еженедельно"
        case "weekly_days": return "Конкретные дни"
        case "monthly": return "Ежемесячно"
        case "interval": return "Каждые N минут"
        case "cron": return "По расписанию cron"
        default: return "По расписанию"
        }
    }

    /// Подпись правила рутины: сначала серверная, иначе — своя.
    public static func ruleLabel(for schedule: ApiSchedule) -> String {
        if let label = schedule.ruleLabel, !label.isEmpty { return label }
        if schedule.ruleKind == "weekly_days", let expr = schedule.ruleExpr,
           let days = parseWeekdays(expr), !days.isEmpty {
            return weekdaysTitle(days)
        }
        if schedule.ruleKind == "interval", let expr = schedule.ruleExpr {
            return "Каждые \(intervalText(expr))"
        }
        if schedule.ruleKind == "weekly" || schedule.ruleKind == "monthly" {
            return fallbackRuleLabel(kind: schedule.ruleKind, expr: schedule.ruleExpr)
        }
        return ruleKindTitle(schedule.ruleKind)
    }

    /// «завтра, 09:00» / «сегодня, 09:00» / «12.11, 09:00» — время в зоне
    /// самой рутины, а не в зоне телефона.
    public static func nextRunLabel(nextRunAt: String?, timezone: String, now: Date = Date()) -> String? {
        guard let date = DateFormats.iso8601(nextRunAt) else { return nil }
        return relativeLabel(date, timezone: timezone, now: now)
    }

    /// «Последний запуск: 21.10» — дата в зоне рутины.
    public static func lastRunLabel(lastRunAt: String?, timezone: String) -> String? {
        guard let date = DateFormats.iso8601(lastRunAt) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
    }

    /// Интервал в форме сервера: «15m», «2h».
    public static func intervalExpr(minutes: Int) -> String {
        let value = max(minimumIntervalMinutes, minutes)
        if value % 60 == 0 { return "\(value / 60)h" }
        return "\(value)m"
    }

    /// Человеческий интервал: «15 минут», «2 часа».
    public static func intervalText(_ expr: String) -> String {
        let trimmed = expr.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("h"), let value = Int(trimmed.dropLast()) {
            return "\(value) \(value == 1 ? "час" : (value < 5 ? "часа" : "часов"))"
        }
        if trimmed.hasSuffix("m"), let value = Int(trimmed.dropLast()) {
            return "\(value) \(value == 1 ? "минута" : (value < 5 ? "минуты" : "минут"))"
        }
        return expr
    }

    /// Минуты из интервала в форме сервера («15m» → 15).
    public static func intervalMinutes(_ expr: String?) -> Int? {
        guard let expr else { return nil }
        let trimmed = expr.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("h"), let value = Int(trimmed.dropLast()) { return value * 60 }
        if trimmed.hasSuffix("m"), let value = Int(trimmed.dropLast()) { return value }
        return nil
    }

    /// День недели для правила «Еженедельно» — как у сервера: 1 = понедельник.
    public static func weekdayExpr(_ day: Int) -> String {
        String(min(max(day, 1), 7))
    }

    /// День месяца для правила «Ежемесячно» — «15» означает 15-е число.
    public static func monthDayExpr(_ day: Int) -> String {
        String(min(max(day, 1), 31))
    }

    /// Сегодняшний день недели в зоне рутины (1 = понедельник) — значение
    /// по умолчанию для правила «Еженедельно».
    public static func todayWeekday(timezone: String, now: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        // weekday в григорианском календаре: 1 = воскресенье. Сервер ждёт
        // 1 = понедельник, поэтому переводим: воскресенье → 7.
        let sundayFirst = calendar.component(.weekday, from: now)
        return sundayFirst == 1 ? 7 : sundayFirst - 1
    }

    /// Сегодняшнее число в зоне рутины — значение по умолчанию для правила
    /// «Ежемесячно».
    public static func todayMonthDay(timezone: String, now: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        return calendar.component(.day, from: now)
    }

    /// Запасная подпись правила, когда сервер её не прислал: та же
    /// формулировка, что у сервера, иначе подписи веба и iOS разойдутся.
    public static func fallbackRuleLabel(kind: String, expr: String?) -> String {
        switch kind {
        case "weekly":
            guard let day = expr.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
                  (1...7).contains(day) else { return ruleKindTitle(kind) }
            return "Еженедельно: \(weekdayTitle(day))"
        case "monthly":
            guard let day = expr.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
                  (1...31).contains(day) else { return ruleKindTitle(kind) }
            return "Ежемесячно: \(day)-е число"
        default:
            return ruleKindTitle(kind)
        }
    }

    /// Полное название дня недели по-русски — как у сервера в подписи правила.
    public static func weekdayTitle(_ day: Int) -> String {
        let names = [
            "понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье",
        ]
        guard (1...7).contains(day) else { return "" }
        return names[day - 1]
    }

    /// Дни недели в форме сервера: «1,3,5» (1 = понедельник).
    public static func weekdaysExpr(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }

    /// Разбор «1,3,5» в набор номеров дней.
    public static func parseWeekdays(_ expr: String?) -> Set<Int>? {
        guard let expr, !expr.isEmpty else { return nil }
        let parts = expr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ (1...7).contains($0) }) else { return nil }
        return Set(parts)
    }

    /// «Пн, Ср, Пт» — подпись дней для клиента.
    public static func weekdaysTitle(_ days: Set<Int>) -> String {
        let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        let ordered = days.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }
        return ordered.joined(separator: ", ")
    }

    /// Время запуска «09:00» → минуты от полуночи.
    ///
    /// Формат — как на сервере (`parseTimeLocal` в `runtime/schedules/rules.ts`):
    /// час — одна или две цифры, минуты — ровно две. Клиент и сервер проверяют
    /// время одинаково, иначе клиент примет значение, которое сервер отвергнет.
    public static func minutesFromTimeLocal(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              (1...2).contains(parts[0].count), parts[1].count == 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0...23).contains(hours), (0...59).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }

    /// Минуты от полуночи → «09:00».
    public static func timeLocalText(_ minutes: Int) -> String {
        let clamped = max(0, min(24 * 60 - 1, minutes))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// Понятное название часового пояса.
    public static func timezoneTitle(_ timezone: String) -> String {
        switch timezone {
        case "Europe/Moscow": return "Москва"
        case "Europe/Kaliningrad": return "Калининград"
        case "Europe/Samara": return "Самара"
        case "Europe/Yekaterinburg": return "Екатеринбург"
        case "Asia/Almaty": return "Алматы"
        case "Asia/Novosibirsk": return "Новосибирск"
        case "Asia/Vladivostok": return "Владивосток"
        case "Europe/Berlin": return "Берлин"
        case "UTC": return "UTC"
        default: return timezone
        }
    }

    /// Зоны, которые предлагает форма (список из спеки — короткий и понятный).
    public static let timezones = [
        "Europe/Moscow",
        "Europe/Kaliningrad",
        "Europe/Berlin",
        "Asia/Almaty",
        "Asia/Novosibirsk",
        "Asia/Vladivostok",
        "UTC",
    ]

    /// Тост по результату запуска: подпись и причина от сервера.
    ///
    /// Причину сервер отдаёт в `detail` — например «прошлый экземпляр не
    /// закрыт». Без неё владелец видит «Пропущено» и не понимает, что
    /// мешает; с ней — «Пропущено: прошлый экземпляр не закрыт».
    public static func runNotice(status: String, detail: String?) -> String {
        let title = runStatusTitle(status)
        // Успехный запуск пояснения не требует: «Задача создана: карточка
        // создана» — тавтология.
        if status == "created" { return title }
        guard let detail, !detail.trimmingCharacters(in: .whitespaces).isEmpty else { return title }
        return "\(title): \(detail)"
    }

    /// Подпись результата запуска из истории.
    public static func runStatusTitle(_ status: String) -> String {
        switch status {
        case "created": return "Задача создана"
        case "skipped": return "Пропущено"
        case "failed": return "Не удалось"
        case "error": return "Ошибка"
        default: return status
        }
    }

    private static func relativeLabel(_ date: Date, timezone: String, now: Date) -> String {
        let zone = TimeZone(identifier: timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)

        let dayDelta = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: date)).day ?? 0
        switch dayDelta {
        case 0:
            return "сегодня, \(time)"
        case 1:
            return "завтра, \(time)"
        default:
            formatter.dateFormat = "dd.MM"
            return "\(formatter.string(from: date)), \(time)"
        }
    }
}
