import Foundation

// «Входящие» (владелец 28.10.2026, переделка 29.10.2026, наводящая строка
// 29.10.2026): ответ сервера `GET /api/attention` — три статуса, на которые
// владелец обязан смотреть: «Заблокировано», «В работе», «На проверке».
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
}
