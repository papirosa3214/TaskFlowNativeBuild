import Foundation

// LOCK-175, этап 1: клиент серверного рантайма (Pi-фасад).
//
// Контракты — `server/src/routes/runtime.ts`. Все пути живут под `/api`,
// общий префикс добавляет `APIClient`.
//
// Экраны сюда пока не ходят — это задел под этапы 2–8. Здесь только
// транспорт и разбор ответов; никаких решений «какая модель лучше» клиент
// не принимает.
//
// Provider credentials TaskFlow iOS НЕ хранит и не видит: POST auth лишь
// инициирует flow, дальше статус читается с сервера.

/// Ответ `PUT /api/runtime/routing/:role`.
public struct RuntimeRoutingUpdate: Codable, Sendable, Hashable {
    public let role: String
    public let primary: String
    public let fallbacks: [String]
}

private struct RuntimeStatusEnvelope: Decodable { let runtime: RuntimeStatus }
private struct RuntimeProfilesEnvelope: Decodable { let profiles: [AgentProfile] }
private struct RuntimeModelsEnvelope: Decodable { let models: [RuntimeModel] }
private struct RuntimeProvidersEnvelope: Decodable { let providers: [RuntimeProvider] }

public extension APIClient {

    // MARK: - Runtime status

    /// `GET /api/runtime/status` — online/offline, версия, endpoint.
    func runtimeStatus() async throws -> RuntimeStatus {
        let envelope: RuntimeStatusEnvelope = try await request(.get, "/runtime/status")
        return envelope.runtime
    }

    // MARK: - AgentProfile

    /// `GET /api/runtime/profiles` — все профили агентов (роли).
    func runtimeProfiles() async throws -> [AgentProfile] {
        let envelope: RuntimeProfilesEnvelope = try await request(.get, "/runtime/profiles")
        return envelope.profiles
    }

    /// `GET /api/runtime/profiles/:id` — один профиль. `id` — роль.
    func runtimeProfile(id: String) async throws -> AgentProfile {
        try await request(.get, "/runtime/profiles/\(id)")
    }

    // MARK: - Models

    /// `GET /api/runtime/models` — каталог моделей Pi с признаком
    /// `available`. Pi недоступен → сервер отвечает 503.
    func runtimeModels() async throws -> [RuntimeModel] {
        let envelope: RuntimeModelsEnvelope = try await request(.get, "/runtime/models")
        return envelope.models
    }

    // MARK: - Providers

    /// `GET /api/runtime/providers` — провайдеры со статусом подключения.
    func runtimeProviders() async throws -> [RuntimeProvider] {
        let envelope: RuntimeProvidersEnvelope = try await request(.get, "/runtime/providers")
        return envelope.providers
    }

    /// `POST /api/runtime/providers/:provider/auth`.
    ///
    /// Без `apiKey` — старт OAuth: сервер отвечает 202 и `authSessionId`,
    /// дальше события читаются отдельно. С `apiKey` — ключ пишется сразу,
    /// ответ содержит `status`/`authType`. Обе формы разбирает
    /// `ProviderAuthStart`, у которого все поля опциональны.
    func startProviderAuth(
        provider: String,
        apiKey: String? = nil
    ) async throws -> ProviderAuthStart {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: String]? = (trimmed?.isEmpty == false) ? ["apiKey": trimmed!] : nil
        return try await request(
            .post, "/runtime/providers/\(provider)/auth", body: body
        )
    }

    /// `GET /api/runtime/auth/:id` — polling-снимок сессии (фолбэк без SSE).
    func runtimeAuthSession(id: String) async throws -> AuthSession {
        try await request(.get, "/runtime/auth/\(id)")
    }

    /// `POST /api/runtime/auth/:id/input` — ответ на запрос Pi
    /// (`manual_code`/`text`/`secret`/`select`). Сервер отвечает 202.
    func submitProviderAuthInput(sessionID: String, value: String) async throws {
        let _: APIOkResponse = try await request(
            .post, "/runtime/auth/\(sessionID)/input", body: ["value": value] as [String: String]
        )
    }

    /// `DELETE /api/runtime/auth/:id` — отмена сессии, ответ 204 без тела.
    func cancelProviderAuth(sessionID: String) async throws {
        try await requestVoid(.delete, "/runtime/auth/\(sessionID)")
    }

    // MARK: - Routing (owner)

    /// `PUT /api/runtime/routing/:role` — primary + упорядоченные fallback'и.
    /// Порядок сохраняется как прислан, сервер его не сортирует.
    @discardableResult
    func updateRuntimeRouting(
        role: String,
        primary: String,
        fallbacks: [String]
    ) async throws -> RuntimeRoutingUpdate {
        try await request(
            .put,
            "/runtime/routing/\(role)",
            body: [
                "primary": .string(primary),
                "fallbacks": .array(fallbacks.map { .string($0) }),
            ] as [String: JSONValue]
        )
    }

    /// `PUT /api/runtime/routing/:role` только с основной моделью: запасные
    /// роли сервер оставляет как есть (на них держится автопереключение при
    /// лимите). `primary` — «голый» id или ссылка `провайдер/модель`.
    @discardableResult
    func updateRuntimeRoutingPrimary(role: String, primary: String) async throws -> RuntimeRoutingUpdate {
        try await request(
            .put,
            "/runtime/routing/\(role)",
            body: ["primary": .string(primary)] as [String: JSONValue]
        )
    }

    /// `PUT /api/runtime/routing` — основная модель сразу всем ролям.
    /// Запасные каждой роли не трогаются.
    func updateRuntimeRoutingAll(primary: String) async throws {
        let _: RuntimeRoutingAllUpdate = try await request(
            .put,
            "/runtime/routing",
            body: ["primary": .string(primary)] as [String: JSONValue]
        )
    }
}

private struct RuntimeRoutingAllUpdate: Decodable { let primary: String }

// MARK: - Автопереключение моделей (владелец 07.10.2026)

/// Провайдер, который сейчас в лимите. `until` — UTC-строка SQLite;
/// `held` — автовозврат выключен, метка не истечёт сама.
public struct FailoverLimit: Codable, Sendable, Hashable, Identifiable {
    public let provider: String
    public let until: String
    public let held: Bool
    public let mode: String
    public let reason: String?
    public var id: String { provider }
}

/// Состояние роли: на какой модели она работает сейчас (с учётом лимитов).
public struct FailoverRoleState: Codable, Sendable, Hashable, Identifiable {
    public let role: String
    public let primary: String
    public let fallbacks: [String]
    public let current: String
    public let onFallback: Bool
    public var id: String { role }

    enum CodingKeys: String, CodingKey {
        case role, primary, fallbacks, current
        case onFallback = "on_fallback"
    }
}

/// Остаток лимита у провайдера, который его отдаёт (12.10.2026).
/// `known == false` — провайдер остаток не сообщает, тогда `limited` ни о чём
/// не говорит: лимита может и не быть, а может быть.
public struct ProviderQuotaState: Codable, Sendable, Hashable, Identifiable {
    public let provider: String
    public let known: Bool
    public let limited: Bool
    public let resetAt: String?
    public let detail: String?
    public var id: String { provider }

    enum CodingKeys: String, CodingKey {
        case provider, known, limited, detail
        case resetAt = "reset_at"
    }

    /// Через сколько минут провайдер обещает ожить (nil — не обещал).
    public var minutesToReset: Int? {
        guard let resetAt else { return nil }
        let iso = ISO8601DateFormatter().date(from: resetAt)
            ?? DateFormatter().date(from: resetAt.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")) as Date?
        guard let iso else { return nil }
        return max(0, Int(iso.timeIntervalSinceNow / 60))
    }
}

/// Нерабочий ключ провайдера; `at` — когда последний заход упал (nil — ключа нет совсем).
public struct ProviderKeyProblem: Codable, Sendable, Hashable, Identifiable {
    public let provider: String
    public let reason: String
    public let at: String?
    public var id: String { provider }
}

/// `GET /api/runtime/failover`.
public struct FailoverStatus: Codable, Sendable, Hashable {
    public let autoSwitch: Bool
    public let autoReturn: Bool
    public let limits: [FailoverLimit]
    public let roles: [FailoverRoleState]
    /// Остатки у провайдеров, которые их отдают; остальные сюда не попадают.
    /// Необязательное: поле появилось позже, прежние сборки сервера его не шлют.
    public let quota: [ProviderQuotaState]?
    /// Провайдеры с нерабочим ключом (20.10.2026): ключ не подключён или
    /// последний заход роли упал отказом доступа. Прежние сборки сервера не шлют.
    public let keyProblems: [ProviderKeyProblem]?

    enum CodingKeys: String, CodingKey {
        case limits, roles, quota
        case keyProblems = "key_problems"
        case autoSwitch = "auto_switch"
        case autoReturn = "auto_return"
    }

    /// Остатки; пусто у прежних сборок сервера.
    public var quotas: [ProviderQuotaState] { quota ?? [] }

    /// Что сейчас мешает провайдеру работать: лимит или ключ; nil — ничего не известно.
    public func problem(of provider: String) -> String? {
        if let key = keyProblems?.first(where: { $0.provider == provider }) { return key.reason }
        if limits.contains(where: { $0.provider == provider }) { return "в лимите" }
        if quotas.contains(where: { $0.provider == provider && $0.known && $0.limited }) { return "в лимите" }
        return nil
    }
}

private struct FailoverToggles: Decodable { let autoSwitch: Bool; let autoReturn: Bool
    enum CodingKeys: String, CodingKey { case autoSwitch = "auto_switch", autoReturn = "auto_return" }
}

public extension APIClient {
    /// Тумблеры, провайдеры в лимите и состояние ролей.
    func failoverStatus() async throws -> FailoverStatus {
        try await request(.get, "/runtime/failover")
    }

    /// `PUT /api/runtime/failover` — общие тумблеры; не переданный не меняется.
    func setFailover(autoSwitch: Bool? = nil, autoReturn: Bool? = nil) async throws {
        var body: [String: JSONValue] = [:]
        if let autoSwitch { body["auto_switch"] = .bool(autoSwitch) }
        if let autoReturn { body["auto_return"] = .bool(autoReturn) }
        let _: FailoverToggles = try await request(.put, "/runtime/failover", body: body)
    }

    /// «Вернуть сейчас»: снять метку лимита у провайдера.
    func releaseProviderLimit(_ provider: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/runtime/failover/limits/\(provider)")
    }
}
