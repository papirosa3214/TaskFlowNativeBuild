import Foundation

// LOCK-246: только чтение графа совместной работы для карточки задачи.
// Контракт — `server/src/routes/task-collaboration-plans.ts`. Runtime-
// состояние узлов (LOCK-246 читал его из `task-role-slots.ts`) с
// 29.09.2026 — обычные подзадачи, см. `subtasks(taskId:)` в
// `APIClient+Subtasks.swift` и `CollaborationPlan.swift`.

private struct CollaborationPlansEnvelope: Decodable { let plans: [ApiCollaborationPlan] }
private struct CollaborationPlanEnvelope: Decodable { let plan: ApiCollaborationPlan }

public extension APIClient {

    /// `GET /api/tasks/:id/collaboration-plans` — все revisions, новые
    /// первыми. Карточке нужна только approved (см. `CollaborationPlanView`).
    func collaborationPlans(taskId: String) async throws -> [ApiCollaborationPlan] {
        let envelope: CollaborationPlansEnvelope = try await request(.get, "/tasks/\(taskId)/collaboration-plans")
        return envelope.plans
    }

    /// `POST /api/tasks/:id/collaboration-plans/:planId/approve` — LOCK-249.
    /// Сервер сам проверяет владельца (403 иначе); клиент только показывает
    /// кнопку владельцу. Утверждение сразу материализует узлы плана как
    /// подзадачи и стартует корневые узлы графа.
    @discardableResult
    func approveCollaborationPlan(taskId: String, planId: String) async throws -> ApiCollaborationPlan {
        let envelope: CollaborationPlanEnvelope = try await request(.post, "/tasks/\(taskId)/collaboration-plans/\(planId)/approve")
        return envelope.plan
    }
}
