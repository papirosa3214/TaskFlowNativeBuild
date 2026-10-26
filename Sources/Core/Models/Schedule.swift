import Foundation

// Рутина (крон-задача) — модель клиента по серверному контракту
// `/api/schedules` (заметка «Рутины и расписание TaskFlow», разделы 4 и 6;
// серверная часть — `server/src/routes/schedules.ts`).
//
// Важно: подпись правила (`rule_label`) приходит с сервера — веб и iOS берут
// одну и ту же строку, иначе подписи разойдутся (дизайн, п. 2.9).

/// Шаблон карточки, которую рутина создаёт при запуске.
public struct ApiSchedulePayload: Codable, Hashable {
    public var title: String
    public var description: String?
    public var projectId: String?
    public var assigneeId: String?
    public var priority: Int?
    public var durationMin: Int?
    public var labels: [String]?
    public var requiresReviewerReview: Bool?
    public var needsResearch: Bool?

    public init(
        title: String,
        description: String? = nil,
        projectId: String? = nil,
        assigneeId: String? = nil,
        priority: Int? = nil,
        durationMin: Int? = nil,
        labels: [String]? = nil,
        requiresReviewerReview: Bool? = nil,
        needsResearch: Bool? = nil
    ) {
        self.title = title
        self.description = description
        self.projectId = projectId
        self.assigneeId = assigneeId
        self.priority = priority
        self.durationMin = durationMin
        self.labels = labels
        self.requiresReviewerReview = requiresReviewerReview
        self.needsResearch = needsResearch
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        // PATCH объединяет шаблон с прежним: отсутствие ключа сохраняет
        // старое значение, поэтому снятие настройки передаём как null.
        try container.encode(description, forKey: .description)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(assigneeId, forKey: .assigneeId)
        try container.encode(durationMin, forKey: .durationMin)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(requiresReviewerReview, forKey: .requiresReviewerReview)
        try container.encodeIfPresent(needsResearch, forKey: .needsResearch)
    }

    enum CodingKeys: String, CodingKey {
        case title, description
        case projectId = "project_id"
        case assigneeId = "assignee_id"
        case priority
        case durationMin = "duration_min"
        case labels
        case requiresReviewerReview = "requires_reviewer_review"
        case needsResearch = "needs_research"
    }
}

/// Сама рутина: правило, время запуска, следующий запуск, статус.
public struct ApiSchedule: Decodable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let taskPayload: ApiSchedulePayload
    public let ruleKind: String
    public let ruleExpr: String?
    /// Текст правила по-русски с сервера. Необязателен: на сервере старше
    /// этой правки поля нет — тогда клиент берёт свой запасной вариант.
    public let ruleLabel: String?
    public let timeLocal: String
    public let timezone: String
    public let nextRunAt: String?
    public let lastRunAt: String?
    public let status: String
    public let catchUp: Bool
    public let overlapPolicy: String
    /// Последний созданный экземпляр рутины — по нему видно, что прошлый
    /// запуск ещё не закрыт.
    public let currentTaskId: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, status, timezone
        case taskPayload = "task_payload"
        case ruleKind = "rule_kind"
        case ruleExpr = "rule_expr"
        case ruleLabel = "rule_label"
        case timeLocal = "time_local"
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case catchUp = "catch_up"
        case overlapPolicy = "overlap_policy"
        case currentTaskId = "current_task_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public var isPaused: Bool { status == "paused" }
}

/// Запуск рутины из истории (`schedule_runs`).
public struct ApiScheduleRun: Decodable, Identifiable, Hashable {
    public let id: String
    public let scheduleId: String?
    public let runAt: String
    public let taskId: String?
    public let status: String
    public let detail: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, detail
        case scheduleId = "schedule_id"
        case runAt = "run_at"
        case taskId = "task_id"
        case createdAt = "created_at"
    }
}

/// Превью правила: ближайший запуск и подпись считает сервер.
public struct ApiSchedulePreview: Decodable, Hashable {
    public let nextRunAt: String?
    public let timezone: String
    public let ruleLabel: String?

    enum CodingKeys: String, CodingKey {
        case timezone
        case nextRunAt = "next_run_at"
        case ruleLabel = "rule_label"
    }
}

/// Тело `POST /api/schedules`.
public struct ApiScheduleCreateRequest: Encodable {
    public var title: String
    public var ruleKind: String
    public var ruleExpr: String?
    public var timeLocal: String
    public var timezone: String
    public var catchUp: Bool
    public var overlapPolicy: String
    public var taskPayload: ApiSchedulePayload

    public init(
        title: String,
        ruleKind: String,
        ruleExpr: String?,
        timeLocal: String,
        timezone: String,
        catchUp: Bool,
        overlapPolicy: String,
        taskPayload: ApiSchedulePayload
    ) {
        self.title = title
        self.ruleKind = ruleKind
        self.ruleExpr = ruleExpr
        self.timeLocal = timeLocal
        self.timezone = timezone
        self.catchUp = catchUp
        self.overlapPolicy = overlapPolicy
        self.taskPayload = taskPayload
    }

    enum CodingKeys: String, CodingKey {
        case title, timezone
        case ruleKind = "rule_kind"
        case ruleExpr = "rule_expr"
        case timeLocal = "time_local"
        case catchUp = "catch_up"
        case overlapPolicy = "overlap_policy"
        case taskPayload = "task_payload"
    }
}

public struct ApiScheduleResponse: Decodable {
    public let schedule: ApiSchedule
}

/// Ответ `POST /api/schedules/:id/run-now`.
public struct ApiScheduleRunNowResponse: Decodable {
    public let ok: Bool
    public let schedule: ApiSchedule
    public let run: ApiScheduleRun?

    enum CodingKeys: String, CodingKey {
        case ok, schedule, run
    }
}
