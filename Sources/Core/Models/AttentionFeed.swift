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
    case answer(chatID: String?, questionID: String)
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
        // Вопрос — запись в таблице: отвечать можно и без чата (13.11.2026).
        if let question, question.status == "open",
           nonempty(question.id) != nil, !question.questions.isEmpty {
            return .answer(chatID: nonempty(chat_id), questionID: question.id)
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

    /// The same brief for every ticket. Source names and full text live at the destination.
    var cardTitle: String {
        switch kind {
        case "question": "Нужен ответ"
        case "approval": id.hasPrefix("plan-op:") ? "Изменить план" : "Согласовать план"
        case "decision": "Ход заблокирован"
        default: "Нужно решение"
        }
    }

    var sourceTitle: String {
        if kind == "question", chat_id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return "В чате"
        }
        switch action {
        case .answer, .chat: return "В чате"
        case .task: return "По задаче"
        case nil: return "Источник недоступен"
        }
    }

    var cardSummary: String? {
        let candidates: [String]
        if kind == "approval" { candidates = [body] }
        else if kind == "question" {
            candidates = (question?.questions.map(\.question) ?? []) + [title, body]
        } else { candidates = [title, body] }
        let boilerplate: Set<String> = [
            cardTitle, "Нужно решение", "Вопрос", "Согласование", "Согласовать план работы",
            "Согласовать изменение плана", "Требуется уточнение задачи",
            "Нужно ваше решение для продолжения работы", "Агент ждёт ваших данных или решения"
        ]
        let context = context_title.map(Self.previewLine)
        for candidate in candidates {
            for line in candidate.split(whereSeparator: \.isNewline) {
                let text = Self.previewLine(String(line))
                guard !text.isEmpty, text != context, !boilerplate.contains(text) else { continue }
                guard text.count > 160 else { return text }
                let prefix = String(text.prefix(159))
                let boundary = prefix.lastIndex(where: \.isWhitespace) ?? prefix.endIndex
                return String(prefix[..<boundary]) + "…"
            }
        }
        return nil
    }

    private static func previewLine(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"^\s*[#>]+\s*"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var actionTitle: String {
        switch action {
        case .answer:
            let count = question?.questions.count ?? 1
            let last = count % 10
            let word = (11...14).contains(count % 100) ? "вопросов" :
                last == 1 ? "вопрос" : (2...4).contains(last) ? "вопроса" : "вопросов"
            return count == 1 ? "Ответить" : "Ответить на \(count) \(word)"
        case .chat: return "Открыть чат"
        case .task:
            return kind == "approval" ? "Рассмотреть план" :
                kind == "question" ? "Ответить в задаче" :
                kind == "decision" ? "Разобрать блокировку" : "Открыть задачу"
        case nil: return "Обращение недоступно"
        }
    }
}

/// Stable sections for the inbox; titles appear once above their requests.
struct AttentionTicketSection: Identifiable {
    let title: String
    var tickets: [ApiAttentionTicket]
    var id: String { title }
    var symbol: String {
        switch tickets.first?.kind {
        case "question": "questionmark.bubble"
        case "approval": "checkmark.shield"
        default: "exclamationmark.triangle"
        }
    }

    static func grouping(_ tickets: [ApiAttentionTicket]) -> [Self] {
        var sections: [Self] = []
        for ticket in tickets {
            if let index = sections.firstIndex(where: { $0.title == ticket.cardTitle }) {
                sections[index].tickets.append(ticket)
            } else {
                sections.append(Self(title: ticket.cardTitle, tickets: [ticket]))
            }
        }
        return sections
    }
}
