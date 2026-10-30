import Foundation
import Observation

// Форма рутины: название, правило, время запуска, часовой пояс, что создаст
// задачу. Превью ближайшего запуска считает сервер (`GET /api/schedules/preview`)
// — клиент не повторяет правила расписания.
@MainActor
@Observable
final class RoutineFormViewModel {
    var title = ""
    var instructions = ""
    var onceDate = Date()
    let editingSchedule: ApiSchedule?
    var ruleKind = "daily"
    /// Дни недели для правила «Конкретные дни» (1 = понедельник, как у сервера).
    var weekdays: Set<Int> = []
    /// День недели для правила «Еженедельно» (1 = понедельник).
    var weeklyDay: Int = 1
    /// День месяца для правила «Ежемесячно».
    var monthlyDay: Int = 1
    var intervalMinutes = 15
    /// Время запуска в минутах от полуночи.
    var timeMinutes = 9 * 60
    var timezone = RoutineFormat.localTimezone
    /// Пропускать запуск, пока прошлый экземпляр не закрыт (`overlap_policy`).
    var skipOverlapping = true
    /// Догонять пропущенный запуск (`catch_up`).
    var catchUp = true
    /// Что создаст рутина: шаблон карточки.
    var taskTitle = ""
    var assigneeRoleKey: String?
    var planProfile: String?
    var durationMin: Int?

    var roles: [RoleProfile] = []
    var isSaving = false
    var errorMessage: String?
    var previewLabel: String?
    var previewNextRun: String?

    private let api: APIClient

    /// Снимок формы на момент открытия: по нему решается, показывать ли
    /// галочку сохранения. Владелец 30.10.2026: она появляется только когда
    /// в карточке рутины реально что-то поменяли.
    private var initialSnapshot: Snapshot?

    private struct Snapshot: Equatable {
        let title: String
        let instructions: String
        let onceDate: Date
        let ruleKind: String
        let weekdays: Set<Int>
        let weeklyDay: Int
        let monthlyDay: Int
        let intervalMinutes: Int
        let timeMinutes: Int
        let timezone: String
        let skipOverlapping: Bool
        let catchUp: Bool
        let taskTitle: String
        let assigneeRoleKey: String?
        let planProfile: String?
        let durationMin: Int?
    }

    private var snapshot: Snapshot {
        Snapshot(title: title, instructions: instructions, onceDate: onceDate,
                 ruleKind: ruleKind, weekdays: weekdays, weeklyDay: weeklyDay,
                 monthlyDay: monthlyDay, intervalMinutes: intervalMinutes,
                 timeMinutes: timeMinutes, timezone: timezone,
                 skipOverlapping: skipOverlapping, catchUp: catchUp,
                 taskTitle: taskTitle, assigneeRoleKey: assigneeRoleKey,
                 planProfile: planProfile, durationMin: durationMin)
    }

    var isDirty: Bool {
        guard let initialSnapshot else { return false }
        return snapshot != initialSnapshot
    }

    init(api: APIClient = APIClient(), schedule: ApiSchedule? = nil) {
        editingSchedule = schedule
        self.api = api
        // По умолчанию — сегодняшний день недели и число в зоне рутины:
        // так «Еженедельно» и «Ежемесячно» сразу знают, когда срабатывать.
        self.weeklyDay = RoutineFormat.todayWeekday(timezone: RoutineFormat.localTimezone)
        self.monthlyDay = RoutineFormat.todayMonthDay(timezone: RoutineFormat.localTimezone)
        if let schedule {
            title = schedule.title; ruleKind = schedule.ruleKind
            timezone = schedule.timezone
            taskTitle = schedule.taskPayload.title
            instructions = schedule.taskPayload.description ?? ""
            assigneeRoleKey = schedule.taskPayload.assigneeId
            planProfile = schedule.taskPayload.planProfile
            durationMin = schedule.taskPayload.durationMin
            skipOverlapping = schedule.overlapPolicy == "skip"
            catchUp = schedule.catchUp
            let parts = schedule.timeLocal.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { timeMinutes = parts[0]*60+parts[1] }
            if let expr = schedule.ruleExpr {
                weekdays = Set(expr.split(separator: ",").compactMap { Int($0) })
                weeklyDay = Int(expr) ?? weeklyDay; monthlyDay = Int(expr) ?? monthlyDay
                if expr.hasSuffix("m") { intervalMinutes = Int(expr.dropLast()) ?? 15 }
                else if expr.hasSuffix("h") { intervalMinutes = (Int(expr.dropLast()) ?? 1)*60 }
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(identifier: timezone)
                onceDate = formatter.date(from: expr) ?? Date()
            }
            // Барабан даты показывает ближайший день, подходящий правилу.
            if ruleKind == "weekly" || ruleKind == "monthly" {
                onceDate = Self.nearestDate(ruleKind: ruleKind, weekday: weeklyDay, monthDay: monthlyDay, timezone: timezone)
            }
        }
        initialSnapshot = Snapshot(
            title: title, instructions: instructions, onceDate: onceDate,
            ruleKind: ruleKind, weekdays: weekdays, weeklyDay: weeklyDay,
            monthlyDay: monthlyDay, intervalMinutes: intervalMinutes,
            timeMinutes: timeMinutes, timezone: timezone,
            skipOverlapping: skipOverlapping, catchUp: catchUp,
            taskTitle: taskTitle, assigneeRoleKey: assigneeRoleKey,
            planProfile: planProfile, durationMin: durationMin
        )
    }

    /// Пустая рутина без правила невозможна — проверка одинаковая на клиенте
    /// и на сервере (критерий приёмки 20).
    /// Дата в барабане что-то значит только для этих правил; у остальных
    /// она не сохраняется на сервере (там есть только правило и время).
    var ruleUsesDate: Bool {
        ruleKind == "once" || ruleKind == "weekly" || ruleKind == "monthly"
    }

    var ruleIsValid: Bool {
        switch ruleKind {
        case "weekly_days": return !weekdays.isEmpty
        case "interval": return intervalMinutes >= RoutineFormat.minimumIntervalMinutes
        default: return true
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ruleIsValid
    }

    /// Правило в форме сервера: «1,3,5» для дней, «15m» для интервала,
    /// «3» для дня недели, «15» для дня месяца.
    var ruleExpr: String? {
        switch ruleKind {
        case "once":
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: timezone); formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: onceDate)
        case "weekly_days": return RoutineFormat.weekdaysExpr(weekdays)
        case "weekly": return RoutineFormat.weekdayExpr(weeklyDay)
        case "monthly": return RoutineFormat.monthDayExpr(monthlyDay)
        case "interval": return RoutineFormat.intervalExpr(minutes: intervalMinutes)
        default: return nil
        }
    }

    var timeLocal: String { RoutineFormat.timeLocalText(timeMinutes) }

    /// Повтор в словах редактора срока карточки (`ExistingTaskDueEditor`):
    /// «none» — однократно, «weekdays» — по будням. Интервал и выборочные дни
    /// барабан не предлагает; такие рутины сохраняют правило, пока повтор
    /// не выбран заново.
    var repeatChoice: String {
        get {
            switch ruleKind {
            case "once": return "none"
            case "weekly_days": return weekdays == Set(1...5) ? "weekdays" : ruleKind
            default: return ruleKind
            }
        }
        set {
            switch newValue {
            case "none": ruleKind = "once"
            case "weekdays": ruleKind = "weekly_days"; weekdays = Set(1...5)
            default: ruleKind = newValue
            }
        }
    }

    /// Дата из барабана: день однократного запуска, а для «Еженедельно» и
    /// «Ежемесячно» — день недели и число, с которых рутина повторяется.
    var startDate: Date? {
        get { onceDate }
        set {
            onceDate = newValue ?? Date()
            weeklyDay = RoutineFormat.todayWeekday(timezone: timezone, now: onceDate)
            monthlyDay = RoutineFormat.todayMonthDay(timezone: timezone, now: onceDate)
        }
    }

    /// Минуты запуска для барабана времени (он работает с `Int?`).
    var startMinutes: Int? {
        get { timeMinutes }
        set { timeMinutes = newValue ?? 9 * 60 }
    }

    static func nearestDate(ruleKind: String, weekday: Int, monthDay: Int, timezone: String, now: Date = Date()) -> Date {
        for offset in 0..<62 {
            let date = now.addingTimeInterval(Double(offset) * 86_400)
            if ruleKind == "weekly", RoutineFormat.todayWeekday(timezone: timezone, now: date) == weekday { return date }
            if ruleKind == "monthly", RoutineFormat.todayMonthDay(timezone: timezone, now: date) == monthDay { return date }
        }
        return now
    }

    /// Интервалы, которые предлагает форма: меньше пяти минут планировщик не берёт.
    static let intervalOptions = [5, 10, 15, 30, 45, 60, 120, 180]

    /// nil — «Автоматически»: убираем также прежнее назначение роли,
    /// чтобы PATCH не сохранил скрытого исполнителя рядом с шаблоном.
    func selectPlanTemplate(_ profile: String?) {
        planProfile = profile
        assigneeRoleKey = nil
    }

    func loadRoles() async {
        if roles.isEmpty {
            roles = (try? await api.rolesList()) ?? []
        }
    }

    /// Превью: подпись правила и ближайший запуск считает сервер.
    func refreshPreview() async {
        guard ruleIsValid else {
            previewLabel = nil
            previewNextRun = nil
            return
        }
        do {
            let preview = try await api.schedulePreview(
                ruleKind: ruleKind,
                ruleExpr: ruleExpr,
                timeLocal: timeLocal,
                timezone: timezone
            )
            previewLabel = preview.ruleLabel ?? RoutineFormat.ruleKindTitle(ruleKind)
            previewNextRun = RoutineFormat.nextRunLabel(nextRunAt: preview.nextRunAt, timezone: preview.timezone)
        } catch is CancellationError {
            return
        } catch {
            previewLabel = nil
            previewNextRun = nil
        }
    }

    @discardableResult
    func create() async -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Введите название рутины"
            return false
        }
        guard ruleIsValid else {
            errorMessage = ruleKind == "weekly_days" ? "Выберите хотя бы один день" : "Проверьте правило"
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        // Поля, которых нет в форме (метки, проверка, исследование),
        // сохраняются из исходного шаблона при редактировании.
        var payload = editingSchedule?.taskPayload ?? ApiSchedulePayload(title: name)
        payload.title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? name : taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.description = instructions.isEmpty ? nil : instructions
        payload.assigneeId = assigneeRoleKey
        payload.planProfile = planProfile
        payload.durationMin = durationMin
        let request = ApiScheduleCreateRequest(
            title: name,
            ruleKind: ruleKind,
            ruleExpr: ruleExpr,
            timeLocal: timeLocal,
            timezone: timezone,
            catchUp: catchUp,
            overlapPolicy: skipOverlapping ? "skip" : "allow",
            taskPayload: payload
        )
        do {
            if let editingSchedule {
                let _: ApiScheduleResponse = try await api.request(.patch, "/schedules/\(editingSchedule.id)", body: request)
            } else {
                _ = try await api.createSchedule(request)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = Self.message(error)
            return false
        }
    }

    static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
