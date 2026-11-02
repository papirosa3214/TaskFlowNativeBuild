import Foundation

/// Сводка по исполнителям карточки — «окно исполнителя» на телефоне.
///
/// Сервер собирает всё (роль и её название, состояние, очередь ожидания,
/// активную попытку, вопросы роли, переписку по слоту, можно ли адресовать
/// шаг) и отдаёт человеческим текстом: телефон ничего не разбирает
/// (правка владельца 02.11.2026).
///
/// Контракт — `server/src/routes/coordination.ts`, эндпоинт
/// `GET /api/coordination/tasks/:id/executors` (PR #53).

/// Ответ сервера целиком: карточка, оркестратор и список исполнителей.
public struct TaskExecutorSummary: Decodable, Sendable, Equatable {
    public let taskId: String
    public let taskTitle: String
    public let generatedAt: String
    public let orchestrator: TaskExecutorOrchestrator
    public let executors: [TaskExecutor]
    public let pendingQuestions: [TaskExecutorQuestion]

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskTitle = "task_title"
        case generatedAt = "generated_at"
        case orchestrator
        case executors
        case pendingQuestions = "pending_questions"
    }
}

/// Оркестратор задачи: роль, название и учётка. Слот оркестратора в плане
/// есть только у orchestrated-плана — тогда к нему можно обратиться.
public struct TaskExecutorOrchestrator: Decodable, Sendable, Equatable {
    public let role: String
    public let title: String
    public let executorId: String
    public let slotId: String?
    public let addressable: Bool
    public let addressBlockReason: String?

    enum CodingKeys: String, CodingKey {
        case role, title
        case executorId = "executor_id"
        case slotId = "slot_id"
        case addressable
        case addressBlockReason = "address_block_reason"
    }
}

/// Один исполнитель — один слот плана.
public struct TaskExecutor: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { subtaskId }

    public let subtaskId: String
    public let planNodeKey: String?
    public let title: String
    public let role: String?
    public let roleTitle: String?
    public let executorId: String?
    public let state: String
    public let stateTitle: String
    public let statusText: String
    public let cause: String
    public let done: Bool
    public let skipped: Bool
    public let waitingFor: [String]
    public let notes: String?
    public let attempt: TaskExecutorAttempt
    public let metrics: TaskExecutorMetrics
    public let addressable: Bool
    public let addressBlockReason: String?
    public let pendingMessages: Int
    public let discussionId: String?
    public let questions: [TaskExecutorQuestion]
    public let messages: [TaskExecutorMessage]

    enum CodingKeys: String, CodingKey {
        case subtaskId = "subtask_id"
        case planNodeKey = "plan_node_key"
        case title, role
        case roleTitle = "role_title"
        case executorId = "executor_id"
        case state
        case stateTitle = "state_title"
        case statusText = "status_text"
        case cause, done, skipped, notes
        case waitingFor = "waiting_for"
        case attempt, metrics, addressable
        case addressBlockReason = "address_block_reason"
        case pendingMessages = "pending_messages"
        case discussionId = "discussion_id"
        case questions, messages
    }
}

/// Активная попытка слота: когда началась, когда закончилась, чем.
public struct TaskExecutorAttempt: Decodable, Sendable, Equatable {
    public let startedAt: String?
    public let endedAt: String?
    public let outcome: String?

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case outcome
    }
}

/// Метрики слота: возраст, попытки за окно, задержка heartbeat.
public struct TaskExecutorMetrics: Decodable, Sendable, Equatable {
    public let ageSeconds: Int
    public let attemptsInWindow: Int
    public let heartbeatAge: Int

    enum CodingKeys: String, CodingKey {
        case ageSeconds = "age_seconds"
        case attemptsInWindow = "attempts_in_window"
        case heartbeatAge = "heartbeat_age"
    }
}

/// Вопрос роли, который ждёт владельца.
public struct TaskExecutorQuestion: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let chatId: String
    public let roleKey: String?
    public let roleTitle: String?
    public let createdAt: String
    public let deadlineAt: String?
    public let payload: TaskExecutorQuestionPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case roleKey = "role_key"
        case roleTitle = "role_title"
        case createdAt = "created_at"
        case deadlineAt = "deadline_at"
        case payload
    }
}

/// Тело вопроса: сами вопросы и варианты ответа.
public struct TaskExecutorQuestionPayload: Decodable, Sendable, Equatable {
    public let questions: [TaskExecutorQuestionItem]
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case questions, note
    }
}

/// Один вопрос с вариантами.
public struct TaskExecutorQuestionItem: Decodable, Sendable, Equatable {
    public let question: String
    public let header: String?
    public let options: [TaskExecutorQuestionOption]
    public let multiSelect: Bool

    enum CodingKeys: String, CodingKey {
        case question, header, options
        case multiSelect = "multiSelect"
    }
}

/// Вариант ответа.
public struct TaskExecutorQuestionOption: Decodable, Sendable, Equatable {
    public let label: String
    public let description: String?
}

/// Сообщение темы задачи по этому слоту: что писали исполнителю и что
/// он отвечал.
public struct TaskExecutorMessage: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let createdAt: String
    public let direction: String

    enum CodingKeys: String, CodingKey {
        case id, text, direction
        case createdAt = "created_at"
    }

    /// Сообщение владельца исполнителю.
    public var isFromOwner: Bool { direction == "owner_to_role" }
}
