// LiveActivityService.swift
// Dynamic Island получает изменения по сокету: пока приложение на экране —
// по общему сокету приложения, в фоне — по своему (общий в фоне закрыт).
// Геолокационный keep-alive остаётся, пока есть активные островки;
// ActivityKit сообщает об их завершении/закрытии, и тогда фон освобождается.
// REST нужен при запуске, восстановлении связи и уведомлении об изменении,
// периодического опроса нет. APNs-токен регистрируется, когда он доступен.

import ActivityKit
import Foundation
import UIKit

@available(iOS 16.2, *)
@MainActor
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
            watch(existing, api: api)
            await update(task: task)
            return existing.id
        }

        let state = contentState(for: task)
        let attributes = TaskActivityAttributes(taskId: task.id)
        let content = ActivityContent(state: state, staleDate: staleDate)

        // ДВА ЗАХОДА, И ЭТО НЕ ПЕРЕСТРАХОВКА — так показал лог 10.09.2026.
        //
        // `pushType: .token` просит токен для обновлений с сервера, а это
        // право на пуши (`aps-environment`). Права нет — запрос падает
        // ЦЕЛИКОМ, островок не появляется вовсе. В логе это выглядит так:
        //   с токеном: ОТКАЗ — SessionCore.PermissionsError Code=3
        //   без токена: ЗАПУСТИЛАСЬ
        // Именно на этом владелец увидел «пишет, не удалось вывести».
        //
        // Пока ключей APNs нет (карточка 75448a64), двигать карточку с
        // сервера всё равно нечем — отсутствие токена ничего не отнимает.
        // Появятся права и ключи — первый заход начнёт срабатывать сам,
        // править здесь ничего не придётся.
        let activity: Activity<TaskActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: attributes, content: content, pushType: .token
            )
            Diag.log("[LiveActivity] запущена с пуш-токеном, id=%@")
        } catch {
            Diag.log("[LiveActivity] токен не выдан (%@), поднимаю без него")
            activity = try Activity.request(
                attributes: attributes, content: content, pushType: nil
            )
            Diag.log("[LiveActivity] запущена без токена, id=%@")
        }

        watch(activity, api: api)

        return activity.id
    }

    /// Обновление работает, пока процесс активен, включая keep-alive островка.
    static func update(task: ApiTask) async {
        guard let activity = activity(for: task.id) else { return }
        await activity.update(
            ActivityContent(state: contentState(for: task), staleDate: staleDate)
        )
    }

    /// Выведена ли задача в островок сейчас.
    static func isShown(taskID: String) -> Bool {
        activity(for: taskID) != nil
    }

    static func end(taskID: String, api: APIClient? = nil) async {
        // Clean local resources even if iOS already removed the Activity.
        clearResources(taskID: taskID)
        if let activity = activity(for: taskID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        reconcileBackground()
        try? await api?.dropLiveActivityToken(taskId: taskID)
    }

    static var activityObservers: [String: Task<Void, Never>] = [:]
    private static var tokenObservers: [String: Task<Void, Never>] = [:]
    private static var refreshTasks: [String: Task<Void, Never>] = [:]
    private static var refreshIDs: [String: UUID] = [:]
    private static var dirtyRefreshIDs: Set<String> = []
    /// Свой сокет островка — только для фона: общий сокет приложения в фоне
    /// закрывается. Пока приложение на экране, островок слушает общий сокет:
    /// раньше свой держался открытым и тогда, и телефон получал каждое
    /// событие дважды (аудит синхронизации 06.11.2026).
    private static let realtime = RealtimeClient(allowsBackgroundConnection: true)
    /// Общий сокет приложения. Не задан — островок живёт на своём сокете
    /// всегда, как до 06.11.2026.
    private static weak var foregroundClient: RealtimeClient?
    private static var foregroundObserverID: UUID?
    private static var transportAPI: APIClient?
    private static var lifecycleObservers: [NSObjectProtocol] = []

    /// Подключить общий сокет приложения: на экране островок слушает его.
    static func attachForeground(_ client: RealtimeClient) {
        foregroundClient = client
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification] {
            lifecycleObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    guard let api = transportAPI else { return }
                    syncTransport(api: api, catchUp: true)
                }
            })
        }
    }

    /// Событие сокета для островка — одинаково из общего и своего сокета.
    private static func handle(_ event: RealtimeEvent, api: APIClient) {
        switch event {
        case .connected:
            // Связь поднялась заново — за разрыв события могли потеряться.
            for activity in activeActivities { refresh(taskID: activity.attributes.taskId, api: api) }
        case .taskChanged(let id): refresh(taskID: id, api: api)
        case .taskCreated(let task), .taskUpdated(let task), .taskState(let task), .taskCompleted(let task):
            refresh(taskID: task.id, api: api)
        case .taskDeleted(let id): Task { await end(taskID: id, api: api) }
        default: break
        }
    }

    /// Какой сокет слушать: на экране — общий, в фоне — свой.
    /// `catchUp` — при смене сокета перечитать островки: событие, пришедшее
    /// в момент переключения, не потеряется.
    private static func syncTransport(api: APIClient, catchUp: Bool) {
        transportAPI = api
        guard !activeActivities.isEmpty else { return }
        let inForeground = UIApplication.shared.applicationState != .background
        if inForeground, let client = foregroundClient {
            realtime.disconnect()
            if foregroundObserverID == nil {
                foregroundObserverID = client.addObserver { event in handle(event, api: api) }
            }
        } else {
            detachForeground()
            realtime.connect()
        }
        if catchUp {
            for activity in activeActivities { refresh(taskID: activity.attributes.taskId, api: api) }
        }
    }

    private static func detachForeground() {
        if let id = foregroundObserverID { foregroundClient?.removeObserver(id) }
        foregroundObserverID = nil
    }

    static func restore(api: APIClient) {
        for activity in activeActivities { watch(activity, api: api) }
        reconcileBackground()
    }

    private static var activeActivities: [Activity<TaskActivityAttributes>] {
        Activity<TaskActivityAttributes>.activities.filter {
            $0.attributes.voiceChatID == nil &&
            ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    private static func watch(_ activity: Activity<TaskActivityAttributes>, api: APIClient) {
        let id = activity.attributes.taskId
        guard activityObservers[id] == nil else { return }
        activityObservers[id] = Task {
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    await end(taskID: id, api: api)
                    return
                }
            }
        }
        tokenObservers[id] = Task {
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                try? await api.registerLiveActivityToken(taskId: id, token: token)
            }
        }
        realtime.onEvent = { event in handle(event, api: api) }
        BackgroundKeepAlive.shared.start()
        syncTransport(api: api, catchUp: false)
        refresh(taskID: id, api: api)
    }

    private static func refresh(taskID: String, api: APIClient) {
        guard isShown(taskID: taskID) else { return }
        dirtyRefreshIDs.insert(taskID)
        guard refreshTasks[taskID] == nil else { return }
        let refreshID = UUID()
        refreshIDs[taskID] = refreshID
        refreshTasks[taskID] = Task {
            defer {
                if refreshIDs[taskID] == refreshID {
                    refreshTasks[taskID] = nil
                    refreshIDs[taskID] = nil
                    dirtyRefreshIDs.remove(taskID)
                }
            }
            repeat {
                dirtyRefreshIDs.remove(taskID)
                guard let task = try? await api.task(id: taskID), !Task.isCancelled,
                      isShown(taskID: taskID) else { return }
                if dirtyRefreshIDs.contains(taskID) { continue }
                await receive(task: task, api: api)
                if !dirtyRefreshIDs.contains(taskID) { return }
            } while !Task.isCancelled
        }
    }

    private static func receive(task: ApiTask, api: APIClient) async {
        if task.status == .completed || task.agentState == nil {
            await end(taskID: task.id, api: api)
        } else {
            await update(task: task)
        }
    }

    private static func clearResources(taskID: String) {
        activityObservers.removeValue(forKey: taskID)?.cancel()
        tokenObservers.removeValue(forKey: taskID)?.cancel()
        refreshTasks.removeValue(forKey: taskID)?.cancel()
        refreshIDs[taskID] = nil
        dirtyRefreshIDs.remove(taskID)
    }

    private static func reconcileBackground() {
        guard activeActivities.isEmpty else { return }
        for id in Array(activityObservers.keys) { clearResources(taskID: id) }
        realtime.disconnect()
        detachForeground()
        BackgroundKeepAlive.shared.stop()
    }

    private static func activity(for taskID: String) -> Activity<TaskActivityAttributes>? {
        activeActivities.first { $0.attributes.taskId == taskID }
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
            assigneeSlug: slug(from: task.assigneeName, userID: task.assigneeId ?? currentStepAgentId(of: task)),
            startedAt: startDate(of: task)
        )
    }

    /// Карточка плана не имеет своего исполнителя: работают роли по шагам.
    /// Портрет в островке — у той роли, что делает шаг прямо сейчас, а когда
    /// ни один не бежит — у роли первого невыполненного шага.
    private static func currentStepAgentId(of task: ApiTask) -> String? {
        let step = task.subtasks.first(where: \.isActivelyRunning)
            ?? task.subtasks.first(where: { !$0.done })
        return step?.agentId
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
    private static func slug(from name: String?, userID: String? = nil) -> String? {
        // Роли и Помощник владельца: портреты лежат в ассетах расширения под avatar-РОЛЬ.
        if let userID {
            if userID == "u-secretary" { return "secretary" }
            if userID.hasPrefix("role_") {
                let role = String(userID.dropFirst("role_".count))
                let known = ["architect", "builder", "qa", "researcher", "analyst", "critic_verifier", "designer"]
                if known.contains(role) { return role.replacingOccurrences(of: "_", with: "-") }
            }
        }
        guard let name = name?.lowercased() else { return nil }
        if name.contains("оркестратор") || name.contains("orchestrator") { return "orchestrator" }
        for known in ["claude", "hermes", "deepseek", "antigravity", "maksim"] where name.contains(known) {
            return known
        }
        if name.contains("максим") { return "maksim" }
        if name.contains("гермес") { return "hermes" }
        return nil
    }
}
