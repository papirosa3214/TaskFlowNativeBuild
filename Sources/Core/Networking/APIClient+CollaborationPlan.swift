import Foundation

// LOCK-246: только чтение графа совместной работы для карточки задачи.
// Контракт — `server/src/routes/task-collaboration-plans.ts` и
// `server/src/routes/task-role-slots.ts`.

private struct CollaborationPlansEnvelope: Decodable { let plans: [ApiCollaborationPlan] }
private struct RoleSlotsEnvelope: Decodable { let slots: [ApiRoleSlot] }

public extension APIClient {

    /// `GET /api/tasks/:id/collaboration-plans` — все revisions, новые
    /// первыми. Карточке нужна только approved (см. `CollaborationPlanView`).
    func collaborationPlans(taskId: String) async throws -> [ApiCollaborationPlan] {
        let envelope: CollaborationPlansEnvelope = try await request(.get, "/tasks/\(taskId)/collaboration-plans")
        return envelope.plans
    }

    /// `GET /api/tasks/:id/role-slots`.
    func roleSlots(taskId: String) async throws -> [ApiRoleSlot] {
        let envelope: RoleSlotsEnvelope = try await request(.get, "/tasks/\(taskId)/role-slots")
        return envelope.slots
    }
}
