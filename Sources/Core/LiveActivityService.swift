// LiveActivityService.swift
// Островок (Dynamic Island) для задачи в работе.
//
// До 10.09.2026 кнопка «Вывести в Dynamic Island» показывала только тост:
// сам виджет жил в Capacitor-обёртке, а в нативном клиенте таргета не было
// вовсе. Владелец нажал, свернул приложение и увидел пустоту.
//
// Здесь то же самое, что делал прежний мост `LiveActivityPlugin` в обёртке,
// но напрямую из SwiftUI — прослойка на JavaScript нативному клиенту не
// нужна.
//
// ЧТО ДВИГАЕТ КАРТОЧКУ, КОГДА ПРИЛОЖЕНИЕ СВЁРНУТО. Ничего изнутри: фонового
// выполнения у приложения нет. Поэтому активность запускается с
// `pushType: .token`, токен уходит на сервер (`POST /api/live-activity/token`),
// и дальше карточку двигает сервер через APNs (`server/src/apns.ts`, таблица
// `live_activity_tokens` — всё это уже написано и ждёт ключей, карточка
// 75448a64). Без ключей островок покажет состояние на момент запуска и
// будет обновляться, только пока приложение открыто.

import ActivityKit
import Foundation

@available(iOS 16.2, *)
enum LiveActivityService {
    /// Система может запретить активности целиком (настройка в «Face ID и
    /// код-пароль» → «Live Activities»), и тогда запрос падает с ошибкой.
    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// После этого момента iOS рисует карточку приглушённо: данные считаются
    /// устаревшими. Каждый пуш с сервера отодвигает границу — если сервер
    /// замолчал, человек это видит, а не принимает старые цифры за свежие.
    private static var staleDate: Date { Date().addingTimeInterval(15 * 60) }

    @discardableResult
    static func start(for task: ApiTask, api: APIClient) async throws -> String {
        // Уже есть островок по этой задаче — не плодим второй, а обновляем.
        if let existing = activity(for: task.id) {
            await update(task: task)
            return existing.id
        }

        let state = contentState(for: task)
        let activity = try Activity.request(
            attributes: TaskActivityAttributes(taskId: task.id),
            content: ActivityContent(state: state, staleDate: staleDate),
            pushType: .token
        )

        // Токен приходит не сразу и меняется со временем — поэтому слушаем
        // поток, а не берём одно значение. Сервер перезаписывает его по
        // task_id, точка отсчёта таймера при этом не сдвигается.
        Task.detached {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                try? await api.registerLiveActivityToken(taskId: task.id, token: token)
            }
        }

        return activity.id
    }

    /// Обновление изнутри приложения: работает, пока оно открыто. Свёрнутое
    /// приложение карточку не двигает — этим занимается сервер по токену.
    static func update(task: ApiTask) async {
        guard let activity = activity(for: task.id) else { return }
        await activity.update(
            ActivityContent(state: contentState(for: task), staleDate: staleDate)
        )
    }

    static func end(taskID: String, api: APIClient? = nil) async {
        guard let activity = activity(for: taskID) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        try? await api?.dropLiveActivityToken(taskId: taskID)
    }

    private static func activity(for taskID: String) -> Activity<TaskActivityAttributes>? {
        Activity<TaskActivityAttributes>.activities.first { $0.attributes.taskId == taskID }
    }

    // MARK: Состояние карточки

    /// ПРОГРЕСС СЧИТАЕТСЯ ПО ДОЧЕРНИМ ЗАДАЧАМ, ЕСЛИ ОНИ ЕСТЬ.
    ///
    /// С 10.09.2026 разбиение родительской задачи — это её дочерние карточки,
    /// а не шаги (серверная задача a195895d). Считать по шагам значило бы
    /// показать в островке ноль у задачи, где работа идёт полным ходом.
    private static func contentState(for task: ApiTask) -> TaskActivityAttributes.ContentState {
        let kids = task.children ?? []
        let total = kids.isEmpty ? task.subtasks.count : kids.count
        let done = kids.isEmpty
            ? task.subtasks.filter(\.done).count
            : kids.filter { $0.status == .completed }.count

        let status = task.agentState?.rawValue ?? "in_progress"
        return TaskActivityAttributes.ContentState(
            status: status,
            statusLabel: label(for: status),
            currentSubtask: task.subtasks.first { !$0.done }?.title,
            totalSubtasks: total,
            doneSubtasks: done,
            progress: total > 0 ? Double(done) / Double(total) : 0,
            assigneeName: task.assigneeName ?? "Агент",
            assigneeInitials: task.assigneeInitials ?? "А",
            assigneeColor: task.assigneeColor ?? "#3A82F6",
            taskTitle: task.title,
            projectName: task.projectName,
            projectColor: task.projectColor,
            updatedAt: Date(),
            assigneeSlug: slug(from: task.assigneeName),
            startedAt: startDate(of: task)
        )
    }

    private static func label(for status: String) -> String {
        switch status {
        case "review": return "На проверке"
        case "blocked": return "Заблокирована"
        case "completed": return "Выполнена"
        default: return "В работе"
        }
    }

    /// Счётчик времени в островке идёт от момента, когда агент взял задачу.
    /// Сервер отдаёт его в списке (`agent_started_at`) — поле заведено именно
    /// ради этой карточки. Нет значения — считаем от «сейчас».
    private static func startDate(of task: ApiTask) -> Date {
        guard let raw = task.agentStartedAt else { return Date() }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
            ?? Date()
    }

    /// Имя картинки в ассетах расширения: сети у Live Activity нет, аватарку
    /// по ссылке не забрать, поэтому в островок кладутся заранее ужатые файлы
    /// (avatar-claude и прочие), а сюда идёт только короткое имя. Незнакомое
    /// имя — нарисуется буква, как и раньше.
    private static func slug(from name: String?) -> String? {
        guard let name = name?.lowercased() else { return nil }
        for known in ["claude", "hermes", "deepseek", "antigravity", "maksim"] where name.contains(known) {
            return known
        }
        if name.contains("максим") { return "maksim" }
        if name.contains("гермес") { return "hermes" }
        return nil
    }
}
