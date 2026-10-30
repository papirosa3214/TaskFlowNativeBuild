import Foundation

/// Снимок данных экранов Composio: каталог сервисов, роли и доступ ролей к
/// каталогу. Снимается одним заходом и достаётся всем экранам сразу.
struct ComposioCatalogSnapshot: Sendable {
    let roles: [RoleProfile]
    let overview: ComposioConnectionOverview
    /// Доступ ролей к каталогу — как его знает сервер на момент снимка.
    /// После правки доступа он меняется здесь же: сервер правку принял,
    /// значит и общий ответ должен её знать, иначе следующий экран вернёт
    /// прежнее состояние.
    var policies: [String: ComposioAccessPolicy]

    init(roles: [RoleProfile], overview: ComposioConnectionOverview,
         policies: [String: ComposioAccessPolicy]) {
        self.roles = roles
        self.overview = overview
        self.policies = policies
    }

    /// Доступ ролей к каталогу — из ответа сервера и списка ролей.
    static func policies(from overview: ComposioConnectionOverview,
                         roles: [RoleProfile]) -> [String: ComposioAccessPolicy] {
        let access = Dictionary((overview.roles ?? []).map { ($0.role, $0) }, uniquingKeysWith: { _, latest in latest })
        return Dictionary(uniqueKeysWithValues: roles.map { role in
            (role.role, ComposioAccessPolicy(enabled: access[role.role]?.enabled ?? false, toolkits: access[role.role]?.toolkits))
        })
    }
}

/// Общий кэш каталога Composio — один на все экраны («Интеграции»,
/// «Composio», «Все интеграции»).
///
/// Раньше у каждого экрана был свой экземпляр модели и свой запрос
/// `GET /api/integrations/composio`: три одинаковых запроса одного каталога и
/// ожидание 5–6 секунд при каждом возврате на экран (30.10.2026). Теперь
/// ответ общий: пока он свежий, экраны берут его отсюда и сеть не трогают, а
/// параллельные запросы склеиваются в один — как в `RolesCache`.
///
/// Хранилище прежнее — общий `ResponseCache`: он уже кладёт туда ответы GET
/// и переживает перезапуск приложения, поэтому после перезапуска экран
/// показывает прошлый каталог сразу, а обновление идёт следом.
actor ComposioCatalogCache {
    static let shared = ComposioCatalogCache()

    /// Сколько живёт ответ: столько же, сколько кэш сервера (60 с). Дальше
    /// каталог считается устаревшим — экран показывает прошлый ответ и
    /// обновляет его в фоне.
    static let ttl: TimeInterval = 60

    /// Ключи ответов в `ResponseCache`: `GET /api/integrations/composio` и
    /// `GET /api/roles?all=1&projection=list`.
    private static let catalogKey = ResponseCache.key(path: "/integrations/composio", query: [])
    private static let rolesKey = ResponseCache.key(
        path: "/roles",
        query: [URLQueryItem(name: "all", value: "1"), URLQueryItem(name: "projection", value: "list")]
    )

    private struct RolesEnvelope: Decodable { let roles: [RoleProfile] }

    private let ttl: TimeInterval
    private let cache: ResponseCache
    private var stored: (at: Date, snapshot: ComposioCatalogSnapshot)?
    private var inflight: Task<ComposioCatalogSnapshot, Error>?

    init(cache: ResponseCache = .shared, ttl: TimeInterval = ComposioCatalogCache.ttl) {
        self.cache = cache
        self.ttl = ttl
    }

    /// Свежий ответ — сеть не нужна. nil, если ответа нет или он старше TTL.
    func fresh() -> ComposioCatalogSnapshot? {
        guard let stored, Date().timeIntervalSince(stored.at) < ttl else { return nil }
        return stored.snapshot
    }

    /// Прошлый ответ — показать сразу, не дожидаясь сети: из памяти, а после
    /// перезапуска приложения — из `ResponseCache`.
    func previous() -> ComposioCatalogSnapshot? {
        if let stored { return stored.snapshot }
        guard let data = cache.data(for: Self.catalogKey),
              let overview = try? JSONDecoder().decode(ComposioConnectionOverview.self, from: data)
        else { return nil }
        let roles = cache.data(for: Self.rolesKey)
            .flatMap { try? JSONDecoder().decode(RolesEnvelope.self, from: $0).roles } ?? []
        return ComposioCatalogSnapshot(
            roles: roles,
            overview: overview,
            policies: ComposioCatalogSnapshot.policies(from: overview, roles: roles)
        )
    }

    /// Записать в общий ответ новое состояние доступа ролей: сервер правку
    /// принял — значит, и общий ответ должен её знать.
    func updatePolicies(_ policies: [String: ComposioAccessPolicy]) {
        guard let stored else { return }
        var snapshot = stored.snapshot
        snapshot.policies = policies
        self.stored = (stored.at, snapshot)
    }

    /// Взять снимок: свежий — из кэша, иначе один запрос на всех. `force` —
    /// обойти TTL: каталог берут заново после правки (кнопка «Обновить»,
    /// подключение сервиса, возврат из браузера с авторизацией).
    func snapshot(
        force: Bool = false,
        fetch: @escaping @Sendable () async throws -> ComposioCatalogSnapshot
    ) async throws -> ComposioCatalogSnapshot {
        if !force, let hit = fresh() { return hit }
        if let running = inflight { return try await running.value }
        let task = Task { try await fetch() }
        inflight = task
        defer { inflight = nil }
        let snapshot = try await task.value
        stored = (Date(), snapshot)
        return snapshot
    }

    /// Забыть ответ — следующий запрос пойдёт в сеть.
    func invalidate() { stored = nil }
}
