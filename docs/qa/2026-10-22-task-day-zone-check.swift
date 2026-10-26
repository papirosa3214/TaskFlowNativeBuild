import Foundation

// Проверка срока задачи по часовым поясам устройства.
//
// Собирается вместе с боевыми исходниками клиента:
//
//   swiftc -O docs/qa/2026-10-22-task-day-zone-check.swift \
//           Sources/Core/Common/TaskDay.swift \
//           Sources/Features/Task/Support/TaskDateText.swift \
//           Sources/Core/Common/DateFormats.swift -o /tmp/task-day-check
//
// Печатает по каждой зоне устройства: какой день показал пикер, что
// сохранял клиент ДО правки (старый путь — полночь зоны устройства,
// переведённая в Москву) и что сохраняет клиент СЕЙЧАС (полночь выбранного
// дня в зоне задачи). Старый столбец — это дословно прежняя реализация
// (`TaskDateText.calendarDateStringMoscow` до правки), поэтому таблица сама
// показывает и дефект, и его отсутствие после правки.

/// Прежнее поведение клиента: `Date` → `YYYY-MM-DD` по Москве.
func legacyMoscowDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "Europe/Moscow")!
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

@main
struct TaskDayZoneCheck {
    static func main() {
    let deviceZones = [
        "Europe/Moscow",
        "Europe/Berlin",
        "Asia/Dubai",
        "Asia/Kolkata",
        "Asia/Tokyo",
        "Australia/Perth",
        "Pacific/Auckland",
        "America/New_York",
        "America/Los_Angeles",
    ]

    /// Один и тот же момент для всех зон: 23 октября 2026, 00:30 по Москве.
    let now = ISO8601DateFormatter().date(from: "2026-10-22T21:30:00Z")!

    print("зона устройства | пикер показал | сохранял раньше | сохраняет сейчас | круг сервер→клиент→сервер")
    var failures = 0

    for identifier in deviceZones {
        let device = TimeZone(identifier: identifier)!

        // Полночь «сегодня» в зоне устройства — то, что клиент клал в срок
        // по умолчанию (быстрое добавление) и что отдавал пикер.
        let deviceMidnight = TaskDay.calendar(device).startOfDay(for: now)
        let picked = TaskDay.string(from: deviceMidnight, timeZone: device)

        // Старый путь: полночь устройства → московская строка.
        let legacy = legacyMoscowDateString(deviceMidnight)

        // Новый путь: день, который показал пикер, → полночь этого дня в зоне
        // задачи → строка для сервера.
        let stored = TaskDay.instant(forPickerDay: deviceMidnight, deviceTimeZone: device)
        let saved = TaskDay.string(from: stored)

        // Круг «сервер → клиент → сервер»: срок с сервера показывается в пикере
        // и сохраняется обратно тем же числом.
        let fromServer = TaskDay.date(from: "2026-10-22")!
        let shown = TaskDay.pickerDate(forTaskDay: fromServer, deviceTimeZone: device)
        let shownDay = TaskDay.string(from: shown, timeZone: device)
        let roundTrip = TaskDay.string(
            from: TaskDay.instant(forPickerDay: shown, deviceTimeZone: device)
        )

        let ok = saved == picked && roundTrip == "2026-10-22" && shownDay == "2026-10-22"
        if !ok { failures += 1 }
        print(
            "\(identifier.padding(toLength: 22, withPad: " ", startingAt: 0))"
            + "| \(picked)          | \(legacy)          | \(saved)          | \(roundTrip)"
            + (ok ? "" : "  ← ОШИБКА")
        )
    }

    print(failures == 0 ? "ИТОГ: во всех зонах выбранный день сохраняется верно" : "ИТОГ: ошибок — \(failures)")
    exit(failures == 0 ? 0 : 1)

    }
}
