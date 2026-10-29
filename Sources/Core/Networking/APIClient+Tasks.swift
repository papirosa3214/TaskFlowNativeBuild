import Foundation

/// Мутации задач сервер отдаёт в обёртке `{ "task": ApiTask }`.
/// GET списка и GET одной карточки остаются не обёрнутыми.
private struct TaskResponse: Decodable {
    let task: ApiTask
}

private struct TaskHeartbeatResponse: Decodable {
    let leaseExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case leaseExpiresAt = "lease_expires_at"
    }
}

private struct StructureTaskRequest: Encodable {
    let text: String
}

/// Задачи — spec/API.md §5.1, и агентский протокол работы над задачей — §5.2/§7.
public extension APIClient {

    /// Результат `POST /ai/structure-task`: локальная модель превращает
    /// свободный текст в поля формы задачи (spec/API.md §5.11).
    struct StructuredTask: Decodable, Sendable, Equatable {
        public let title: String
        public let description: String?
        public let subtasks: [String]
        public let dueDate: String?
        public let priority: Int?

        enum CodingKeys: String, CodingKey {
            case title, description, subtasks, priority
            case dueDate
        }
    }

    /// Проекция ответа со списком задач.
    ///
    /// `.list` — лёгкий ответ для экрана списка: без подзадач, описание в
    /// одну строку, вместо подзадач — два числа (29.10.2026, «телефон —
    /// чисто окошко»). `.full` — прежний полный ответ.
    public enum TaskListProjection: String, Sendable {
        case list
        case full
    }

    /// `includeChildren` — query `include_children` (spec §5.1).
    func tasks(includeChildren: Bool = false, archived: Bool = false,
               projection: TaskListProjection = .list) async throws -> [ApiTask] {
        var query: [URLQueryItem] = []
        if includeChildren { query.append(URLQueryItem(name: "include_children", value: "true")) }
        if archived { query.append(URLQueryItem(name: "archived", value: "true")) }
        if projection == .list { query.append(URLQueryItem(name: "projection", value: "list")) }
        return try await request(.get, "/tasks", query: query)
    }

    /// Список задач с ETag и курсором синхронизации (вариант B трафика
    /// iOS-клиента, владелец 25.10.2026).
    ///
    /// Если список не менялся, сервер отвечает 304 без тела — клиент не
    /// качает 402 КБ gzip впустую. Курсор (`X-TaskFlow-Sync-Cursor`) нужен
    /// для дельты: по нему клиент спрашивает «что изменилось с прошлого
    /// раза» вместо полной перечитки.
    struct TaskListPage: Sendable {
        let tasks: [ApiTask]
        let notModified: Bool
        let cursor: String?
        let etag: String?
    }

    /// `projection=list` — лёгкий ответ для списка (29.10.2026, «телефон —
    /// чисто окошко»).
    ///
    /// Сервер в списке не присылает подзадачи и обрезает описание до одной
    /// строки: подзадачи были 1,85 МБ из 2,9 МБ ответа, а строка рисует
    /// только чип «2/5 шагов». Вместо подзадач приходят два числа.
    ///
    /// На сервере без проекции (старый) ответ прежний, и клиент считает шаги
    /// по пришедшим подзадачам — так он работает с обоими.
    func taskList(includeChildren: Bool = false, archived: Bool = false, etag: String? = nil,
                  projection: TaskListProjection = .list) async throws -> TaskListPage {
        var query: [URLQueryItem] = []
        if includeChildren { query.append(URLQueryItem(name: "include_children", value: "true")) }
        if archived { query.append(URLQueryItem(name: "archived", value: "true")) }
        if projection == .list { query.append(URLQueryItem(name: "projection", value: "list")) }
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = etag }
        let (data, http) = try await requestRaw(
            .get, "/tasks", query: query, acceptedErrorStatuses: [304], headers: headers
        )
        let cursor = http.value(forHTTPHeaderField: "X-TaskFlow-Sync-Cursor")
        let newEtag = http.value(forHTTPHeaderField: "ETag")
        if http.statusCode == 304 {
            // Курсор при 304 берём только из заголовка: ETag — это отпечаток
            // тела, а не метка времени, и подставлять его в курсор нельзя
            // (сервер поймёт его как мусор и попросит полную перечитку).
            return TaskListPage(tasks: [], notModified: true, cursor: cursor, etag: newEtag ?? etag)
        }
        let tasks = try decode([ApiTask].self, from: data)
        return TaskListPage(tasks: tasks, notModified: false, cursor: cursor, etag: newEtag)
    }

    /// ДЕЛЬТА: что изменилось с курсора (вариант B трафика iOS-клиента).
    ///
    /// Сервер отдаёт id, а не карточки: изменившиеся клиент дозапрашивает
    /// по одной тем же путём, что и по событию сокета (`GET /api/tasks/:id`),
    /// исчезнувшие — просто убирает. `full: true` — журнал не покрывает
    /// запрошенный момент, нужен обычный полный список.
    struct TaskChanges: Decodable, Sendable {
        let serverTime: String
        let changedIds: [String]
        let removedIds: [String]
        let full: Bool

        enum CodingKeys: String, CodingKey {
            case serverTime = "server_time"
            case changedIds = "changed_ids"
            case removedIds = "removed_ids"
            case full
        }
    }

    func taskChanges(since: String) async throws -> TaskChanges {
        try await request(.get, "/tasks/changes", query: [URLQueryItem(name: "since", value: since)])
    }

    /// 404, если задача не видна по роли вызывающего (spec §2.3).
    func task(id: String) async throws -> ApiTask {
        try await request(.get, "/tasks/\(id)")
    }

    func structureTask(text: String) async throws -> StructuredTask {
        try await request(.post, "/ai/structure-task", body: StructureTaskRequest(text: text), timeout: APIClient.aiTimeout)
    }

    /// Тело создания — строго типизированная структура (в отличие от PATCH,
    /// здесь все поля известны заранее, партиальность не нужна).
    ///
    /// 13.09.2026, владелец: «нажимаю готово, а задача не сохраняется». Причина
    /// — дефолтный авто-сгенерированный `Encodable` пишет ВСЕ опциональные
    /// поля как `null`, а сервер (`server/src/routes/tasks.ts`) для `subtasks`
    /// и `label_ids` требует именно массив (или отсутствие ключа), а не
    /// `null`. Сервер отвечал 400 `{"error":"subtasks должен быть массивом"}`,
    /// клиент ловил ошибку в `TaskStore.create`, возвращал `nil`, шторка
    /// оставалась открытой — выглядело как «не сохраняется». Ручной
    /// `encode(to:)` ниже ОПУСКАЕТ `nil`-значения вместо записи `null`,
    /// чтобы тело в JSON совпадало с тем, что подразумевает сервер.
    struct NewTaskRequest: Encodable, Sendable {
        public var title: String
        public var description: String?
        public var dueDate: String?
        public var startTime: String?
        public var durationMin: Int?
        public var projectId: String?
        public var assigneeId: String?
        public var priority: Int?
        public var parentId: String?
        public var labelIds: [String]?
        public var subtasks: [String]?
        public var runRepeat: String?
        public var repeatUntil: String?
        public var requiresReviewerReview: Bool?

        enum CodingKeys: String, CodingKey {
            case title, description
            case dueDate = "due_date"
            case startTime = "start_time"
            case durationMin = "duration_min"
            case projectId = "project_id"
            case assigneeId = "assignee_id"
            case priority
            case parentId = "parent_id"
            case labelIds = "label_ids"
            case subtasks
            case runRepeat = "run_repeat"
            case repeatUntil = "repeat_until"
            case requiresReviewerReview = "requires_reviewer_review"
        }

        public init(
            title: String, description: String? = nil, dueDate: String? = nil,
            startTime: String? = nil, durationMin: Int? = nil, projectId: String? = nil,
            assigneeId: String? = nil, priority: Int? = nil, parentId: String? = nil,
            labelIds: [String]? = nil, subtasks: [String]? = nil,
            runRepeat: String? = nil, repeatUntil: String? = nil,
            requiresReviewerReview: Bool? = nil
        ) {
            self.title = title; self.description = description; self.dueDate = dueDate
            self.startTime = startTime; self.durationMin = durationMin; self.projectId = projectId
            self.assigneeId = assigneeId; self.priority = priority; self.parentId = parentId
            self.labelIds = labelIds; self.subtasks = subtasks
            self.runRepeat = runRepeat; self.repeatUntil = repeatUntil
            self.requiresReviewerReview = requiresReviewerReview
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(title, forKey: .title)
            if let v = description { try c.encode(v, forKey: .description) }
            if let v = dueDate { try c.encode(v, forKey: .dueDate) }
            if let v = startTime { try c.encode(v, forKey: .startTime) }
            if let v = durationMin { try c.encode(v, forKey: .durationMin) }
            if let v = projectId { try c.encode(v, forKey: .projectId) }
            if let v = assigneeId { try c.encode(v, forKey: .assigneeId) }
            if let v = priority { try c.encode(v, forKey: .priority) }
            if let v = parentId { try c.encode(v, forKey: .parentId) }
            if let v = labelIds { try c.encode(v, forKey: .labelIds) }
            if let v = subtasks { try c.encode(v, forKey: .subtasks) }
            if let v = runRepeat { try c.encode(v, forKey: .runRepeat) }
            if let v = repeatUntil { try c.encode(v, forKey: .repeatUntil) }
            if let v = requiresReviewerReview { try c.encode(v, forKey: .requiresReviewerReview) }
        }
    }

    func createTask(_ payload: NewTaskRequest) async throws -> ApiTask {
        let response: TaskResponse = try await request(.post, "/tasks", body: payload)
        return response.task
    }

    /// Партиальное обновление — `[String: JSONValue]`, а не типизированная
    /// структура: PATCH шлёт РОВНО те поля, что нужно поменять (см. комментарий
    /// в `JSONValue`). Разрешённые поля сервером — `title, description,
    /// due_date, start_time, duration_min, project_id, parent_id, priority,
    /// assignee_id, status, position, pinned` (остальные молча игнорируются).
    /// ⚠️ Смена `status` требует роль owner/orchestrator — агенту 403 (spec §9 п.1).
    func patchTask(id: String, fields: [String: JSONValue]) async throws -> ApiTask {
        let response: TaskResponse = try await request(.patch, "/tasks/\(id)", body: fields)
        return response.task
    }

    /// Совместимый вход обычного удаления: теперь всегда архивирует.
    /// Не использовать DELETE как запасной путь при недоступном архиве.
    func deleteTask(id: String) async throws {
        _ = try await archiveTask(id: id)
    }

    func archiveTask(id: String) async throws -> ApiTask {
        let response: TaskResponse = try await request(.post, "/tasks/\(id)/archive", body: [String: JSONValue]())
        return response.task
    }

    func restoreTask(id: String) async throws -> ApiTask {
        let response: TaskResponse = try await request(.post, "/tasks/\(id)/restore", body: [String: JSONValue]())
        return response.task
    }

    /// Используется только для подтверждённого удаления карточки из архива.
    func permanentlyDeleteTask(id: String) async throws {
        struct PurgeResponse: Decodable { let deleted: Bool }
        let response: PurgeResponse = try await request(.delete, "/tasks/\(id)", body: [String: JSONValue]())
        guard response.deleted else { throw APIError.server(status: 409, message: "Сервер не подтвердил окончательное удаление.") }
    }

    /// «✓ Запустить» на карточке Помощника владельца: сервер поднимает флаг дереву
    /// черновика и отдаёт карточки с учётом очереди; личные дела не трогает.
    func startDraft(taskID: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request(.post, "/task-intake/drafts/\(taskID)/start")
    }

    /// Ручной разовый запуск агента на карточке — только владелец.
    /// `mode`: `executor` — поднять исполнителя, `reviewer` — верификатора.
    /// Служба-будильник при этом может быть выключена: это одиночный заход
    /// по команде владельца, автоматику он не включает.
    func runTask(id: String, mode: String) async throws {
        let _: APIOkResponse = try await request(
            .post, "/tasks/\(id)/run", body: ["mode": JSONValue.string(mode)]
        )
    }

    /// Продлить серию повтора на следующий календарный год (владелец):
    /// «повторять до 31 декабря следующего» и снова разрешить воркеру
    /// создавать следующее вхождение.
    func extendRepeat(id: String) async throws {
        let _: APIOkResponse = try await request(.post, "/tasks/\(id)/repeat-extend")
    }

    /// Запуск серверного конвейера глубокого исследования (владелец;
    /// задача должна быть помечена `needs_research`). Сервер поднимает
    /// отдельный процесс и сразу отвечает: план → сбор → проверка → синтез →
    /// отчёт в секции «Отчёты» карточки.
    func startResearch(id: String) async throws {
        let _: APIOkResponse = try await request(.post, "/tasks/\(id)/research")
    }

    // MARK: - Агентский протокол (spec §5.2/§7) — на карточке задачи владелец
    // видит статус агента/аренду, поэтому клиенту нужно уметь их читать; сами
    // мутации (claim/heartbeat/state) пригодятся экрану «Работа агента».

    func claimTask(id: String, sessionId: String? = nil) async throws -> ApiTask {
        var body: [String: JSONValue] = [:]
        if let sessionId { body["session_id"] = .string(sessionId) }
        let response: TaskResponse = try await request(.post, "/tasks/\(id)/claim", body: body)
        return response.task
    }

    /// Сервер не возвращает задачу для heartbeat, только новый срок аренды.
    func heartbeatTask(id: String, sessionId: String? = nil) async throws -> String? {
        var body: [String: JSONValue] = [:]
        if let sessionId { body["session_id"] = .string(sessionId) }
        let response: TaskHeartbeatResponse = try await request(.post, "/tasks/\(id)/heartbeat", body: body)
        return response.leaseExpiresAt
    }

    /// Комментарий ОБЯЗАТЕЛЕН при переходе в `blocked`/`review` и при
    /// `review → in_progress` — без него сервер отвечает 400 (spec §7).
    func setTaskAgentState(id: String, state: AgentState?, comment: String? = nil) async throws -> ApiTask {
        var body: [String: JSONValue] = ["state": state.map { JSONValue.string($0.rawValue) } ?? .null]
        if let comment { body["comment"] = .string(comment) }
        let response: TaskResponse = try await request(.post, "/tasks/\(id)/state", body: body)
        return response.task
    }

    func agentRules() async throws -> [String] {
        struct Response: Decodable { let rules: [String] }
        let response: Response = try await request(.get, "/agent/rules")
        return response.rules
    }
}

struct TaskExecutionStatus: Decodable, Equatable {
    let status: String
    let busy: Bool
    let scheme: String?
    let canLaunch: Bool
    let canChangeExecutor: Bool
    let canUsePlan: Bool
    let branchRootTaskId: String?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case status, busy, scheme, error
        case branchRootTaskId = "branch_root_task_id"
        case canLaunch = "can_launch", canChangeExecutor = "can_change_executor", canUsePlan = "can_use_plan"
    }
    var title: String {
        switch status {
        case "queued": "Исполнитель в очереди"
        case "running", "in_progress": "Исполнитель работает"
        case "retry_wait": "Ожидание повторного запуска"
        case "failed": "Не удалось запустить исполнителя"
        case "review": "Результат на проверке"
        case "blocked": "Исполнитель ждёт ответа"
        case "finished": "Заход исполнителя завершён"
        default: "Готово к запуску"
        }
    }
}

extension APIClient {
    func taskExecutionStatus(id: String) async throws -> TaskExecutionStatus {
        try await request(.get, "/tasks/\(id)/execution")
    }
}
