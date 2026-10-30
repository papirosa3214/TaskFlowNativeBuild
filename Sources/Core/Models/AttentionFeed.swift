import Foundation

// GET /api/attention: tickets — открытые обращения к владельцу (30.10.2026).
// Группы статусов ниже сохранены для совместимости со старым сервером;
// новый экран не выдаёт их за входящие обращения.
//
// Модели вынесены из экрана, чтобы контракт можно было проверить на хосте:
// сервер отдаёт наводящую строку (`hint`) — что делать с задачей, не открывая
// карточку, и данные для строки как в остальных списках (роль, приоритет,
// шаги). Старого сервера без этих полей клиент переживает: их просто нет.

struct ApiAttentionTask: Decodable, Identifiable {
    let id: String
    let title: String
    let project: String?
    let role: String?
    let age_seconds: Int?
    let overdue: Bool?
    /// Наводящая строка: что делать с задачей прямо сейчас.
    let hint: String?
    /// Идентификатор исполнителя (`role_qa`, `u-secretary`) — по нему
    /// телефон рисует аватар роли.
    let role_id: String?
    /// Приоритет задачи (1 — срочный … 4 — низкий).
    let priority: Int?
    /// Шаги задачи: сколько всего и сколько закрыто.
    let subtask_total: Int?
    let subtask_done: Int?

    /// Что рисуем под названием задачи. Пустая строка не рисуется вовсе.
    var hintLine: String? {
        guard let hint else { return nil }
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Инициалы для аватара, когда картинки роли нет: первые буквы двух
    /// первых слов названия роли («Лайф-тестировщик» → «ЛТ»).
    var roleInitials: String? {
        guard let role, !role.isEmpty else { return nil }
        let words = role
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
        guard !words.isEmpty else { return nil }
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

struct ApiAttentionGroup: Decodable, Identifiable {
    let key: String
    let title: String
    let count: Int
    let tasks: [ApiAttentionTask]
    /// Идентификатор для `ForEach` — ключ группы. Без него структура не
    /// соответствует `Identifiable`, и проект не собирается (внесено
    /// коммитом b5cce4a6 29.10.2026).
    var id: String { key }
}

struct ApiAttention: Decodable {
    let ok: Bool
    let groups: [ApiAttentionGroup]
    /// nil means the server still exposes the old task-status feed.
    let tickets: [ApiAttentionTicket]?
}

enum AttentionTicketAction: Equatable {
    case answer(chatID: String, questionID: String)
    case task(String)
    case chat(String)
}

struct ApiAttentionTicket: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let role: String?
    let role_id: String?
    let task_id: String?
    let chat_id: String?
    let context_title: String?
    let project: String?
    let created_at: String
    let question: ChatQuestion?

    var createdDate: Date? {
        let normalized = created_at.contains("T") ? created_at : created_at.replacingOccurrences(of: " ", with: "T") + "Z"
        return try? Date(normalized, strategy: .iso8601)
    }

    var action: AttentionTicketAction? {
        func nonempty(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        if let chatID = nonempty(chat_id), let question, question.status == "open",
           nonempty(question.id) != nil, !question.questions.isEmpty {
            return .answer(chatID: chatID, questionID: question.id)
        }
        if let taskID = nonempty(task_id) { return .task(taskID) }
        if let chatID = nonempty(chat_id) { return .chat(chatID) }
        return nil
    }

    var kindTitle: String {
        switch kind {
        case "question": "Вопрос"
        case "approval": "Согласование"
        default: "Нужно решение"
        }
    }

    var actionTitle: String {
        switch action {
        case .answer: "Ответить"
        case .chat: "Открыть чат"
        case .task: kind == "approval" ? "Рассмотреть план" : "Открыть задачу"
        case nil: "Обращение недоступно"
        }
    }
}
