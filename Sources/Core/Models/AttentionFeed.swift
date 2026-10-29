import Foundation

// «Входящие» (владелец 28.10.2026, переделка 29.10.2026, наводящая строка
// 29.10.2026): ответ сервера `GET /api/attention` — три статуса, на которые
// владелец обязан смотреть: «Заблокировано», «В работе», «На проверке».
//
// Модели вынесены из экрана, чтобы контракт можно было проверить на хосте:
// сервер отдаёт наводящую строку (`hint`) — что делать с задачей, не открывая
// карточку. Старого сервера без этого поля клиент переживает: строки просто
// не будет.

struct ApiAttentionTask: Decodable, Identifiable {
    let id: String
    let title: String
    let project: String?
    let role: String?
    let age_seconds: Int?
    let overdue: Bool?
    /// Наводящая строка: что делать с задачей прямо сейчас.
    let hint: String?

    /// Что рисуем под названием задачи. Пустая строка не рисуется вовсе.
    var hintLine: String? {
        guard let hint else { return nil }
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
