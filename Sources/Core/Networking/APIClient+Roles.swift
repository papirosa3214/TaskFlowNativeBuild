import Foundation

// LOCK-176, этапы 2–3: серверный каталог ролей — источник экрана «Команда».
// Контракт — `server/src/routes/roles.ts` (`GET /api/roles`).

private struct RolesEnvelope: Decodable { let roles: [RoleProfile] }

/// Общий кэш `GET /api/roles` (20.10.2026). Ответ — 640 КБ с промптами всех
/// ролей, а запрашивали его 8 экранов, карточка задачи — дважды на каждое
/// открытие. Одновременные запросы склеиваются в один, свежий ответ живёт 30 с.
actor RolesCache {
    static let shared = RolesCache()
    private let ttl: TimeInterval = 30
    private var stored: [Bool: (at: Date, roles: [RoleProfile])] = [:]
    private var inflight: [Bool: Task<[RoleProfile], Error>] = [:]

    func roles(all: Bool, fetch: @escaping @Sendable () async throws -> [RoleProfile]) async throws -> [RoleProfile] {
        if let hit = stored[all], Date().timeIntervalSince(hit.at) < ttl { return hit.roles }
        if let running = inflight[all] { return try await running.value }
        let task = Task { try await fetch() }
        inflight[all] = task
        defer { inflight[all] = nil }
        let roles = try await task.value
        stored[all] = (Date(), roles)
        return roles
    }

    func invalidate() { stored.removeAll() }
}

/// `GET /api/roles/:role/models` — список и текущая модель роли.
public struct RoleModels: Decodable {
    public let current: String?
    public let models: [RoleModelOption]
}

public extension APIClient {

    /// `GET /api/roles` — только включённые роли.
    func roles() async throws -> [RoleProfile] {
        try await roles(all: false)
    }

    /// `GET /api/roles?all=1` — вместе с отключёнными: экрану «Команда» их
    /// надо показать, чтобы было что включить обратно. Без `all=1` — только
    /// рабочие роли (LOCK-205, ссылка на `server/src/routes/roles.ts:278-285`).
    func roles(all: Bool) async throws -> [RoleProfile] {
        #if DEBUG
        // UI fixtures must not depend on the mutable live role catalogue or cached titles.
        if ProcessInfo.processInfo.environment["TASKFLOW_ROLE_CONTEXT_FIXTURE"] == "1" {
            let data = Data(#"{"role":"developer","title":"Разработчик","account_id":"role_developer","status":"ready","status_title":"Готов","runtime_ready":true,"problems":[],"prompt":"Инструкция роли","skills":[],"tools":[],"fallbacks":[],"attempt_policy":[],"enabled":true}"#.utf8)
            return [try JSONDecoder().decode(RoleProfile.self, from: data)]
        }
        #endif
        return try await RolesCache.shared.roles(all: all) {
            let query = all ? [URLQueryItem(name: "all", value: "1")] : []
            let envelope: RolesEnvelope = try await self.request(.get, "/roles", query: query)
            return envelope.roles
        }
    }

    /// Сбросить кэш ролей — после правки роли (модель, включение, инструкция).
    static func invalidateRoles() async { await RolesCache.shared.invalidate() }

    /// `GET /api/roles/:role` — одна роль (не используется списком, оставлено
    /// для точечного обновления после смены модели).
    func role(id: String) async throws -> RoleProfile {
        try await request(.get, "/roles/\(id)")
    }

    /// Интеграции Composio роли — блок `integrations` того же профиля. Список
    /// ролей его не отдаёт: сервер спрашивает каталог Composio только для
    /// одной роли.
    func roleIntegrations(id: String) async throws -> RoleIntegrations? {
        struct Envelope: Decodable { let integrations: RoleIntegrations? }
        let envelope: Envelope = try await request(.get, "/roles/\(id)")
        return envelope.integrations
    }

    /// `GET /api/roles/:role/runtime-context` — постоянные правила запуска
    /// роли с серверным происхождением каждого слоя. Карточки, история чатов,
    /// сессии и секреты этим маршрутом намеренно не выдаются.
    func roleRuntimeContext(role: String) async throws -> RoleRuntimeContext {
        try await request(.get, "/roles/\(role)/runtime-context")
    }

    func roleInstructionHistory(role: String, block: String, team: Bool) async throws -> [RoleInstructionHistory] {
        let result: RoleInstructionHistoryEnvelope = try await request(.get, "/runtime/context/\(role)/\(block)", query: [URLQueryItem(name: "scope", value: team ? "command" : "role")])
        return result.history
    }

    func mutateRoleInstruction(role: String, block: String, team: Bool, version: Int, text: String, action: String = "set", historyVersion: Int? = nil) async throws {
        var body: [String: JSONValue] = ["scope": .string(team ? "command" : "role"), "if_match": .number(Double(version)), "text": .string(text)]
        if let historyVersion { body["version"] = .number(Double(historyVersion)) }
        let suffix = action == "set" ? "" : "/\(action)"
        try await requestVoid(action == "set" ? .patch : .post, "/runtime/context/\(role)/\(block)\(suffix)", body: body)
    }

    // MARK: - LOCK-205: создание и правка роли из экрана «Команда»

    /// `POST /api/roles` — только владелец. Сервер сам заводит учётку
    /// `role_<ключ>` (тип `ai`, без пароля и ключа) и обновляет кэш ролей.
    /// Ответ — `RoleProfile` созданной роли (см. `rolesManage.test.ts`:
    /// - `201`, поля `role`/`title`/`summary`/`enabled` присутствуют).
    ///
    /// Поля `summary` и `prompt` опциональны: пустая строка означает «не
    /// задано», и для `prompt` сервер тогда читает прежний файл
    /// `scripts/role-prompts/<роль>.md`.
    func createRole(key: String, title: String, summary: String?, prompt: String?) async throws -> RoleProfile {
        var body: [String: JSONValue] = [
            "key": .string(key),
            "title": .string(title)
        ]
        if let summary, !summary.isEmpty { body["summary"] = .string(summary) }
        if let prompt, !prompt.isEmpty { body["prompt"] = .string(prompt) }
        return try await request(.post, "/roles", body: body)
    }

    /// Что сделать с инструкцией роли в `PATCH /api/roles/:key`. На сервере
    /// пустая строка и `null` эквивалентны: оба сбрасывают на файл
    /// `scripts/role-prompts/<роль>.md`. `keep` — поле в PATCH не
    /// отправляется, и сервер его не трогает (LOCK-205).
    enum PromptChange {
        /// Поле в PATCH не отправляется (сервер оставляет прежнее значение).
        case keep
        /// Заменить инструкцию на новый текст. Пустая строка тоже
        /// считается заменой — клиент валидирует это ДО отправки.
        case set(String)
        /// Сбросить инструкцию на файл (на сервере это `prompt: ""` или `null`).
        case reset
    }

    /// `PATCH /api/roles/:key` — только владелец. Все поля опциональны,
    /// сервер требует, чтобы хотя бы одно было передано (иначе `422`).
    /// `enabled: false` отключает роль — она пропадает из работы и из
    /// списка без `?all=1`.
    /// `POST /api/external-agents/refresh` — только владелец. Сервер ищет на
    /// машине установленных внешних агентов (Claude Code, Codex, …) и заводит
    /// найденных участниками команды со своей учёткой и иконкой.
    func roleModels(role: String) async throws -> RoleModels {
        try await request(.get, "/roles/\(role)/models")
    }

    func refreshExternalAgents() async throws {
        try await requestVoid(.post, "/external-agents/refresh", body: [String: String]())
    }

    func patchRole(
        role: String,
        title: String? = nil,
        summary: String? = nil,
        prompt: PromptChange = .keep,
        enabled: Bool? = nil
    ) async throws -> RoleProfile {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        if let summary { body["summary"] = .string(summary) }
        switch prompt {
        case .keep:
            break
        case .set(let text):
            body["prompt"] = .string(text)
        case .reset:
            // Сервер принимает `""` или `null` как «сбросить на файл».
            body["prompt"] = .null
        }
        if let enabled { body["enabled"] = .bool(enabled) }
        return try await request(.patch, "/roles/\(role)", body: body)
    }
}

public extension APIClient {
    func roleBehavior(role: String) async throws -> RoleBehavior {
        try await request(.get, "/roles/\(role)/behavior")
    }
    func saveRoleBehaviorTemplate(role: String, name: String, text: String, gender: RoleBehaviorGender) async throws -> RoleBehaviorTemplate {
        try await request(.post, "/roles/\(role)/behavior/templates", body: ["name": name, "text": text, "gender": gender.rawValue])
    }
    func applyRoleBehavior(role: String, text: String, gender: RoleBehaviorGender, expectedVersion: Int) async throws -> RoleBehavior {
        let body: [String: JSONValue] = ["text": .string(text), "gender": .string(gender.rawValue), "expectedVersion": .number(Double(expectedVersion))]
        return try await request(.patch, "/roles/\(role)/behavior", body: body)
    }
}
