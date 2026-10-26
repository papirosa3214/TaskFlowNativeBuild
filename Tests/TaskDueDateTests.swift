import Foundation
import XCTest
@testable import TaskFlow

/// Срок задачи — календарный день (spec/API.md §1), «сегодня» считается по
/// Москве (spec/SCREENS-1.md §4.1). Клиент хранит срок как `Date`, поэтому
/// его приходится переводить между зоной устройства (системный пикер) и зоной
/// задачи (Москва). Пока перевод делался в разных местах и по-разному, день,
/// который пользователь видел в пикере, не совпадал с днём, который уходил на
/// сервер: на телефонах восточнее Москвы дата уезжала на сутки назад.
final class TaskDueDateTests: XCTestCase {

    /// Пикер и «Сегодня/Завтра» дают московскую полночь — это 21:00 UTC
    /// предыдущих суток. На сервер должен уйти выбранный день, а не прошлый.
    func testMoscowMidnightKeepsChosenDay() {
        let chosen = ISO8601DateFormatter().date(from: "2026-09-29T21:00:00Z")!
        XCTAssertEqual(TaskFormViewModel.dueDateString(chosen), "2026-09-30")
    }

    /// Срок, прочитанный с сервера, разбирается в UTC-полночь — при
    /// сохранении без изменений он не должен сдвинуться.
    func testLoadedUTCMidnightKeepsSameDay() {
        let loaded = DateFormats.calendarDate("2026-09-30")!
        XCTAssertEqual(TaskFormViewModel.dueDateString(loaded), "2026-09-30")
    }

    // MARK: Выбранный день доезжает до сервера тем же числом

    /// Главный инвариант: день, который показал пикер, — тот же, что уйдёт
    /// на сервер. Проверяется по всем часовым поясам, где был замечен сдвиг.
    func testSelectedDayIsSavedAsTheSameDayInEveryDeviceZone() {
        for identifier in Self.deviceZoneIdentifiers {
            let device = TimeZone(identifier: identifier)!
            let picked = Self.midnight(2026, 10, 23, in: device)
            let stored = TaskFormViewModel.dueDateFromPicker(picked, deviceTimeZone: device)
            XCTAssertEqual(
                TaskFormViewModel.dueDateString(stored), "2026-10-23",
                "зона устройства \(identifier): выбранный день потерялся"
            )
        }
    }

    /// Обратный путь: срок с сервера показывается в пикере тем же числом.
    /// Раньше на телефонах западнее Москвы пикер показывал предыдущий день.
    func testStoredDayIsShownInPickerAsTheSameDayInEveryDeviceZone() {
        for identifier in Self.deviceZoneIdentifiers {
            let device = TimeZone(identifier: identifier)!
            let stored = TaskDay.date(from: "2026-10-22")
            XCTAssertNotNil(stored)
            let shown = TaskFormViewModel.pickerDateForDisplay(stored!, deviceTimeZone: device)
            XCTAssertEqual(
                TaskDay.string(from: shown, timeZone: device), "2026-10-22",
                "зона устройства \(identifier): пикер показал другой день"
            )
        }
    }

    /// Круг «сервер → клиент → сервер» без изменений: дата не должна
    /// сдвинуться ни в одной зоне устройства.
    func testServerDaySurvivesRoundTripInEveryDeviceZone() {
        for identifier in Self.deviceZoneIdentifiers {
            let device = TimeZone(identifier: identifier)!
            let loaded = TaskDay.date(from: "2026-10-22")!
            let shown = TaskFormViewModel.pickerDateForDisplay(loaded, deviceTimeZone: device)
            let saved = TaskFormViewModel.dueDateString(TaskFormViewModel.dueDateFromPicker(shown, deviceTimeZone: device))
            XCTAssertEqual(saved, "2026-10-22", "зона устройства \(identifier): дата сдвинулась по кругу")
        }
    }

    /// «Сегодня» у задач — по Москве, как на сервере: срок, равный
    /// московскому сегодняшнему дню, считается сегодняшним в любой зоне.
    func testTaskDueTodayIsCountedByMoscowDay() {
        let task = Self.makeTask(dueDate: TaskDay.todayString())
        XCTAssertTrue(task.isDueToday)
    }

    /// Быстрое добавление кладёт срок полночью дня в зоне задачи: полночь
    /// устройства на телефонах восточнее Москвы давала предыдущие сутки.
    func testDefaultDueDateIsMidnightOfTaskZone() {
        let start = TaskDay.startOfDay(Date())
        let moscowHour = TaskDay.calendar(TaskDay.moscow).component(.hour, from: start)
        XCTAssertEqual(moscowHour, 0, "полночь задачи должна быть полуночью по Москве")
        XCTAssertEqual(TaskDay.string(from: start), TaskDay.todayString())
    }

    /// Прежний путь клиента — полночь зоны устройства, переведённая в Москву,
    /// — на телефонах восточнее Москвы терял сутки. Тест фиксирует и сам
    /// дефект, и то, что действующий путь от него избавлен.
    func testLegacyPathShiftedTheDayAndCurrentPathDoesNot() {
        let device = TimeZone(identifier: "Asia/Tokyo")!
        let picked = Self.midnight(2026, 10, 23, in: device)

        // Прежний путь — как было в клиенте до правки.
        let legacy = Self.legacyMoscowDateString(picked)
        XCTAssertEqual(legacy, "2026-10-22", "прежний путь обязан был терять сутки")

        // Действующий путь: день, который показал пикер, доезжает тем же.
        let stored = TaskFormViewModel.dueDateFromPicker(picked, deviceTimeZone: device)
        XCTAssertEqual(TaskFormViewModel.dueDateString(stored), "2026-10-23")
    }

    // MARK: Вспомогательное

    /// Часовые пояса, где дефект был замечен, плюс Москва как контроль.
    private static let deviceZoneIdentifiers = [
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

    private static func midnight(_ year: Int, _ month: Int, _ day: Int, in zone: TimeZone) -> Date {
        TaskDay.calendar(zone).date(
            from: DateComponents(timeZone: zone, year: year, month: month, day: day)
        )!
    }



    /// Прежнее поведение клиента: `Date` → `YYYY-MM-DD` по Москве
    /// (копия того, что было в `TaskDateText` до появления `TaskDay`).
    private static func legacyMoscowDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Задача с сервера — из JSON, как в жизни.
    private static func makeTask(dueDate: String?) -> ApiTask {
        let payload: [String: Any] = [
            "id": "task-1",
            "title": "Задача",
            "status": "active",
            "priority": 0,
            "due_date": dueDate as Any,
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(ApiTask.self, from: data)
    }
}
