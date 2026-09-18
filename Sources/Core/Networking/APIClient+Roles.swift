import Foundation

// LOCK-176, этапы 2–3: серверный каталог ролей — источник экрана «Команда».
// Контракт — `server/src/routes/roles.ts` (`GET /api/roles`).

private struct RolesEnvelope: Decodable { let roles: [RoleProfile] }

public extension APIClient {

    /// `GET /api/roles` — восемь ролей-профилей: статус, модель с fallback,
    /// промпт, tools, скиллы, права, текущая задача.
    func roles() async throws -> [RoleProfile] {
        let envelope: RolesEnvelope = try await request(.get, "/roles")
        return envelope.roles
    }

    /// `GET /api/roles/:role` — одна роль (не используется списком, оставлено
    /// для точечного обновления после смены модели).
    func role(id: String) async throws -> RoleProfile {
        try await request(.get, "/roles/\(id)")
    }
}
