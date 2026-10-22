import EventKit
import Foundation

/// Исполнитель операций устройства через `EventKit` — Apple Напоминания и
/// Apple Календарь.
///
/// Данные лежат только на телефоне, поэтому вся логика доступа — здесь, на
/// устройстве; сервер по контракту `device_op` (§3 заметки
/// ffaf800d-19ad-40e7-8616-9482019f432e) только спрашивает и получает ответ.
///
/// Правила, общие для всех операций:
///  - телефон не додумывает: нет доступа — `access_denied`, нет такого
///    элемента — `not_found`, плохие аргументы — `invalid_arguments`;
///  - даты — ISO 8601 в местном времени владельца с часовым поясом;
///  - идентификаторы Apple возвращаются как есть.
enum AppleEventKitOps {
    // MARK: - Точка входа

    static func perform(op: String, arguments: [String: JSONValue]) async -> DeviceOpOutcome {
        switch op {
        case "reminder.list":
            return await reminderList(arguments)
        case "reminder.create":
            return reminderCreate(arguments)
        case "reminder.complete":
            return reminderComplete(arguments)
        case "reminder.reschedule":
            return reminderReschedule(arguments)
        case "calendar.events":
            return await calendarEvents(arguments)
        case "calendar.event.create":
            return calendarEventCreate(arguments)
        case "calendar.event.update":
            return calendarEventUpdate(arguments)
        default:
            return .failure(
                code: .opUnknown,
                message: "операция «\(op)» на этом устройстве не поддерживается"
            )
        }
    }

    // MARK: - Доступ

    private static func needReminders() -> DeviceOpOutcome? {
        guard AppleEventKitAccess.remindersGranted() else {
            return .failure(
                code: .accessDenied,
                message: "на айфоне не выдан доступ к Напоминаниям"
            )
        }
        return nil
    }

    private static func needCalendar() -> DeviceOpOutcome? {
        guard AppleEventKitAccess.calendarGranted() else {
            return .failure(
                code: .accessDenied,
                message: "на айфоне не выдан доступ к Календарю"
            )
        }
        return nil
    }

    // MARK: - Напоминания

    private static func reminderList(_ args: [String: JSONValue]) async -> DeviceOpOutcome {
        let lists = AppleEventKitAccess.reminderLists()
        var wanted: EKCalendar?
        if let key = args["list"]?.text {
            wanted = lists.first { $0.calendarIdentifier == key || $0.title == key }
            if wanted == nil {
                return .failure(
                    code: .notFound,
                    message: "списка напоминаний «\(key)» на телефоне нет"
                )
            }
        }
        if let denied = needReminders() { return denied }

        let includeCompleted = args["includeCompleted"]?.flag ?? false
        let from = args["from"]?.text.flatMap(DeviceOpDates.parse)
        let to = args["to"]?.text.flatMap(DeviceOpDates.parse)
        let reminders = await AppleEventKitAccess.fetchReminders(in: wanted)

        var items: [JSONValue] = []
        for reminder in reminders {
            if !includeCompleted && reminder.isCompleted { continue }
            let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            if let from, let due, due < from { continue }
            if let to, let due, due > to { continue }
            items.append(reminderJSON(reminder, due: due))
        }
        let listItems: [JSONValue] = lists.map {
            .object([
                "id": .string($0.calendarIdentifier),
                "title": .string($0.title),
            ])
        }
        return .success(.object([
            "lists": .array(listItems),
            "reminders": .array(items),
        ]))
    }

    private static func reminderJSON(_ reminder: EKReminder, due: Date?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(reminder.calendarItemIdentifier),
            "title": .string(reminder.title ?? ""),
            "listId": .string(reminder.calendar?.calendarIdentifier ?? ""),
            "isCompleted": .bool(reminder.isCompleted),
            "notes": .string(reminder.notes ?? ""),
        ]
        if let due {
            fields["dueDate"] = .string(DeviceOpDates.iso(due))
        }
        return .object(fields)
    }

    private static func reminderCreate(_ args: [String: JSONValue]) -> DeviceOpOutcome {
        guard let title = args["title"]?.text, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(
                code: .invalidArguments,
                message: "не хватает названия напоминания (title)"
            )
        }
        if let denied = needReminders() { return denied }

        let store = AppleEventKitAccess.store
        var target: EKCalendar?
        if let key = args["list"]?.text {
            target = AppleEventKitAccess.reminderLists().first {
                $0.calendarIdentifier == key || $0.title == key
            }
            if target == nil {
                return .failure(
                    code: .notFound,
                    message: "списка напоминаний «\(key)» на телефоне нет"
                )
            }
        }

        var dueDate: Date?
        if let raw = args["dueDate"]?.text {
            guard let parsed = DeviceOpDates.parse(raw) else {
                return .failure(
                    code: .invalidArguments,
                    message: "дата напоминания не понята (нужен ISO 8601, например 2026-10-22T09:00:00+03:00)"
                )
            }
            dueDate = parsed
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        if let notes = args["notes"]?.text { reminder.notes = notes }
        reminder.calendar = target ?? store.defaultCalendarForNewReminders()
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        reminder.priority = eventKitPriority(args["priority"]?.double ?? 0)

        do {
            try store.save(reminder, commit: true)
        } catch {
            return .failure(
                code: .internalError,
                message: "не удалось сохранить напоминание: \(error.localizedDescription)"
            )
        }

        var fields: [String: JSONValue] = [
            "id": .string(reminder.calendarItemIdentifier),
            "title": .string(reminder.title ?? title),
        ]
        if let dueDate {
            fields["dueDate"] = .string(DeviceOpDates.iso(dueDate))
        }
        return .success(.object(fields))
    }

    private static func reminderComplete(_ args: [String: JSONValue]) -> DeviceOpOutcome {
        guard let id = args["id"]?.text, !id.isEmpty else {
            return .failure(
                code: .invalidArguments,
                message: "не хватает идентификатора напоминания (id)"
            )
        }
        if let denied = needReminders() { return denied }

        let store = AppleEventKitAccess.store
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            return .failure(
                code: .notFound,
                message: "напоминание с таким идентификатором на телефоне не найдено"
            )
        }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            return .failure(
                code: .internalError,
                message: "не удалось закрыть напоминание: \(error.localizedDescription)"
            )
        }
        return .success(.object([
            "id": .string(id),
            "isCompleted": .bool(true),
        ]))
    }

    private static func reminderReschedule(_ args: [String: JSONValue]) -> DeviceOpOutcome {
        guard let id = args["id"]?.text, !id.isEmpty else {
            return .failure(
                code: .invalidArguments,
                message: "не хватает идентификатора напоминания (id)"
            )
        }
        guard let raw = args["dueDate"]?.text else {
            return .failure(
                code: .invalidArguments,
                message: "не хватает новой даты напоминания (dueDate)"
            )
        }
        guard let due = DeviceOpDates.parse(raw) else {
            return .failure(
                code: .invalidArguments,
                message: "дата напоминания не понята (нужен ISO 8601, например 2026-10-22T09:00:00+03:00)"
            )
        }
        if let denied = needReminders() { return denied }

        let store = AppleEventKitAccess.store
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            return .failure(
                code: .notFound,
                message: "напоминание с таким идентификатором на телефоне не найдено"
            )
        }
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: due
        )
        do {
            try store.save(reminder, commit: true)
        } catch {
            return .failure(
                code: .internalError,
                message: "не удалось перенести напоминание: \(error.localizedDescription)"
            )
        }
        return .success(.object([
            "id": .string(id),
            "title": .string(reminder.title ?? ""),
            "dueDate": .string(DeviceOpDates.iso(due)),
        ]))
    }

    // MARK: - Календарь

    private static func calendarEvents(_ args: [String: JSONValue]) async -> DeviceOpOutcome {
        guard let fromRaw = args["from"]?.text, let toRaw = args["to"]?.text else {
            return .failure(
                code: .invalidArguments,
                message: "нужен период: from и to (ISO 8601)"
            )
        }
        guard let from = DeviceOpDates.parse(fromRaw), let to = DeviceOpDates.parse(toRaw) else {
            return .failure(
                code: .invalidArguments,
                message: "период не понят (нужен ISO 8601, например 2026-10-22T09:00:00+03:00)"
            )
        }
        if let denied = needCalendar() { return denied }

        let store = AppleEventKitAccess.store
        var calendars = AppleEventKitAccess.calendars()
        if let key = args["calendarId"]?.text {
            guard let found = calendars.first(where: { $0.calendarIdentifier == key || $0.title == key }) else {
                return .failure(
                    code: .notFound,
                    message: "календаря «\(key)» на телефоне нет"
                )
            }
            calendars = [found]
        }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        let events = store.events(matching: predicate)
        return .success(.object([
            "events": .array(events.map(eventJSON)),
        ]))
    }

    private static func eventJSON(_ event: EKEvent) -> JSONValue {
        .object([
            "id": .string(event.eventIdentifier ?? ""),
            "title": .string(event.title ?? ""),
            "start": .string(DeviceOpDates.iso(event.startDate)),
            "end": .string(DeviceOpDates.iso(event.endDate)),
            "calendarId": .string(event.calendar?.calendarIdentifier ?? ""),
            "calendarTitle": .string(event.calendar?.title ?? ""),
            "notes": .string(event.notes ?? ""),
            "location": .string(event.location ?? ""),
            "isAllDay": .bool(event.isAllDay),
        ])
    }

    private static func calendarEventCreate(_ args: [String: JSONValue]) -> DeviceOpOutcome {
        guard let title = args["title"]?.text, !title.isEmpty else {
            return .failure(
                code: .invalidArguments,
                message: "не хватает названия события (title)"
            )
        }
        guard let startRaw = args["start"]?.text else {
            return .failure(
                code: .invalidArguments,
                message: "не хватает начала события (start, ISO 8601)"
            )
        }
        guard let start = DeviceOpDates.parse(startRaw) else {
            return .failure(
                code: .invalidArguments,
                message: "начало события не понято (нужен ISO 8601, например 2026-10-22T15:00:00+03:00)"
            )
        }
        if let denied = needCalendar() { return denied }

        let store = AppleEventKitAccess.store
        var target: EKCalendar?
        if let key = args["calendar"]?.text {
            target = AppleEventKitAccess.calendars().first {
                $0.calendarIdentifier == key || $0.title == key
            }
            if target == nil {
                return .failure(
                    code: .notFound,
                    message: "календаря «\(key)» на телефоне нет"
                )
            }
        }
        var end = start.addingTimeInterval(3600)
        if let endRaw = args["end"]?.text {
            guard let parsed = DeviceOpDates.parse(endRaw) else {
                return .failure(
                    code: .invalidArguments,
                    message: "конец события не понят (нужен ISO 8601)"
                )
            }
            end = parsed
        }
        if end <= start { end = start.addingTimeInterval(3600) }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = target ?? store.defaultCalendarForNewEvents
        if let location = args["location"]?.text { event.location = location }
        if let notes = args["notes"]?.text { event.notes = notes }
        if let minutes = args["alertMinutesBefore"]?.double, minutes > 0 {
            event.addAlarm(EKAlarm(relativeOffset: -minutes * 60))
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            return .failure(
                code: .internalError,
                message: "не удалось создать событие: \(error.localizedDescription)"
            )
        }
        return .success(.object([
            "id": .string(event.eventIdentifier ?? ""),
            "title": .string(title),
            "start": .string(DeviceOpDates.iso(event.startDate)),
            "end": .string(DeviceOpDates.iso(event.endDate)),
        ]))
    }

    private static func calendarEventUpdate(_ args: [String: JSONValue]) -> DeviceOpOutcome {
        guard let id = args["id"]?.text, !id.isEmpty else {
            return .failure(
                code: .invalidArguments,
                message: "не хватает идентификатора события (id)"
            )
        }
        if let denied = needCalendar() { return denied }

        let store = AppleEventKitAccess.store
        guard let event = store.event(withIdentifier: id) else {
            return .failure(
                code: .notFound,
                message: "событие с таким идентификатором на телефоне не найдено"
            )
        }

        if let title = args["title"]?.text { event.title = title }
        if let location = args["location"]?.text { event.location = location }
        if let notes = args["notes"]?.text { event.notes = notes }

        var start: Date?
        if let raw = args["start"]?.text {
            guard let parsed = DeviceOpDates.parse(raw) else {
                return .failure(
                    code: .invalidArguments,
                    message: "начало события не понято (нужен ISO 8601)"
                )
            }
            start = parsed
            event.startDate = parsed
        }
        if let raw = args["end"]?.text {
            guard let parsed = DeviceOpDates.parse(raw) else {
                return .failure(
                    code: .invalidArguments,
                    message: "конец события не понят (нужен ISO 8601)"
                )
            }
            event.endDate = parsed
        }
        if let start, event.endDate <= start {
            event.endDate = start.addingTimeInterval(3600)
        }

        // Отмена события: в EventKit нет «отменённого» события — только
        // удаление из календаря. Это единственный способ честно отменить
        // встречу на айфоне.
        if args["cancelled"]?.flag == true {
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                return .failure(
                    code: .internalError,
                    message: "не удалось отменить событие: \(error.localizedDescription)"
                )
            }
            return .success(.object([
                "id": .string(id),
                "cancelled": .bool(true),
            ]))
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            return .failure(
                code: .internalError,
                message: "не удалось сохранить событие: \(error.localizedDescription)"
            )
        }
        var fields: [String: JSONValue] = ["id": .string(id)]
        if let title = event.title { fields["title"] = .string(title) }
        fields["start"] = .string(DeviceOpDates.iso(event.startDate))
        fields["end"] = .string(DeviceOpDates.iso(event.endDate))
        return .success(.object(fields))
    }

    // MARK: - Мелочи

    /// Приоритет контракта (0–9) в приоритет EventKit (0 — без приоритета,
    /// 1 — высокий, 5 — низкий).
    private static func eventKitPriority(_ value: Double) -> Int {
        let rounded = Int(value.rounded())
        if rounded <= 0 { return 0 }
        if rounded >= 5 { return 5 }
        return rounded
    }
}

/// Даты контракта: ISO 8601 в местном времени владельца с часовым поясом
/// (`2026-10-22T09:00:00+03:00`), для «без времени» — только дата
/// (`2026-10-22`).
enum DeviceOpDates {
    /// Разбор даты из команды сервера. Без часового пояса — местное время
    /// владельца.
    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let withZone = ISO8601DateFormatter()
        withZone.formatOptions = [.withInternetDateTime]
        if let date = withZone.date(from: text) { return date }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }

        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone.current
        day.dateFormat = "yyyy-MM-dd"
        if let date = day.date(from: text) { return date }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone.current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: text)
    }

    /// Дата в формате контракта.
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
