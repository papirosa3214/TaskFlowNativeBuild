import Foundation

/// Маршрут сводки по исполнителям карточки.
///
/// Сервер .110 отдаёт всё нужное для окна исполнителя человеческим текстом
/// (роль, состояние, ожидания, вопросы роли, переписка по слоту) — телефон
/// ничего не разбирает (правка владельца 02.11.2026).
/// Контракт — `server/src/routes/coordination.ts`, эндпоинт
/// `GET /api/coordination/tasks/:id/executors` (PR #53).
public extension APIClient {

    /// Что сделали энричеры и эмбеддинги по задаче. Только для владельца.
    internal func taskContextObservability(taskId: String) async throws -> TaskContextObservability {
        try await request(.get, "/coordination/tasks/\(taskId)/context-observability")
    }

    /// `GET /api/coordination/tasks/:id/executors` — сводка по исполнителям.
    func taskExecutorSummary(taskId: String) async throws -> TaskExecutorSummary {
        try await request(.get, "/coordination/tasks/\(taskId)/executors")
    }
}
