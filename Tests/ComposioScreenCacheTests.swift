// Хост-программа собирается отдельно (swiftc + исходники приложения в том же
// модуле), поэтому импорт модуля приложения здесь условный: в бандле тестов
// модуль TaskFlow доступен, в самостоятельной сборке — нет.
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

#if COMPOSIO_HOST_TEST
import Foundation

// Границы подменены: production-модель экрана Composio
// (`ComposioIntegrationsViewModel`) и общий кэш `ComposioCatalogCache`
// компилируются без изменений, сеть заменена удвоенным APIClient, который
// считает запросы. Симулятор не нужен — проверка чистой логики на хосте.

/// Роль — как её отдаёт сервер в лёгкой проекции списка.
struct RoleProfile: Codable, Sendable {
    let role: String
    let title: String
    let enabled: Bool?
    var isEnabled: Bool { enabled ?? true }
}

struct APIError: Error { var errorDescription: String? { "Ошибка сети" } }

final class APIClient: @unchecked Sendable {
    private let lock = NSLock()
    private var _catalogRequests = 0
    private var _roleRequests = 0
    private var _holdCatalog = false
    private var _waiters: [CheckedContinuation<Void, Never>] = []

    var catalogRequests: Int { lock.withLock { _catalogRequests } }
    var roleRequests: Int { lock.withLock { _roleRequests } }
    /// Держать ответ каталога, пока тест не отпустит (проверка параллельной
    /// загрузки двух экранов и показа прошлого ответа без ожидания сети).
    var holdCatalog: Bool {
        get { lock.withLock { _holdCatalog } }
        set { lock.withLock { _holdCatalog = newValue } }
    }
    var waitingRequests: Int { lock.withLock { _waiters.count } }

    /// Отпустить всех, кто ждёт ответа каталога.
    func releaseCatalog() {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            let all = _waiters
            _waiters = []
            return all
        }
        for waiter in waiters { waiter.resume() }
    }

    static let sample = ComposioConnectionOverview(
        catalog: [ComposioToolkit(slug: "github", name: "GitHub", logo: nil, description: nil, connected: true, noAuth: false)],
        services: [],
        configured: true,
        available: true,
        roles: [ComposioWorkspacePolicy(role: "developer", enabled: true, toolkits: nil)],
        catalogCursor: nil,
        catalogTotalPages: 1,
        error: nil
    )

    func composioConnections() async throws -> ComposioConnectionOverview {
        lock.withLock { _catalogRequests += 1 }
        if lock.withLock({ _holdCatalog }) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock { _waiters.append(continuation) }
            }
        }
        return Self.sample
    }

    func rolesList(all: Bool = false) async throws -> [RoleProfile] {
        lock.withLock { _roleRequests += 1 }
        return [RoleProfile(role: "developer", title: "Разработчик", enabled: true)]
    }

    func roleComposio(role: String, search: String = "", cursor: String? = nil, limit: Int? = nil) async throws -> RoleComposio {
        RoleComposio(enabled: true, toolkits: nil, configured: true, available: true, catalog: [], catalogCursor: nil, catalogTotalPages: 1, error: nil)
    }

    func saveRoleComposio(role: String, enabled: Bool, toolkits: [String]?) async throws {}

    func composioLinkAccount(toolkit: String) async throws -> ComposioAuthorization {
        ComposioAuthorization(url: "https://composio.dev/connect")
    }

    func composioAccounts(toolkit: String) async throws -> [ComposioAccount] { [] }

    func composioDeleteAccount(toolkit: String, id: String) async throws {}
}

@main
struct ComposioScreenCacheTests {
    @MainActor
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print("\(ok ? "PASS" : "FAIL"): \(name)")
            if !ok { failures += 1 }
        }

        // 1. Два экрана («Composio» и «Все интеграции») — один запрос каталога.
        let api = APIClient()
        let cache = ComposioCatalogCache(cache: ResponseCache(directory: temporaryDirectory("shared")), ttl: 60)
        let screen = ComposioIntegrationsViewModel(api: api, cache: cache)
        await screen.load()
        check(api.catalogRequests == 1, "первый показ экрана берёт каталог из сети")
        check(screen.loaded && screen.catalog.map(\.slug) == ["github"], "каталог разложен по экрану")
        check(screen.roles.map(\.id) == ["developer"], "роли разложены по экрану")

        let catalogScreen = ComposioIntegrationsViewModel(api: api, cache: cache)
        await catalogScreen.load()
        check(api.catalogRequests == 1, "второй экран делит ответ первого — нового запроса нет")

        // 2. Экран пересоздали (навигация туда-обратно) — запрос не повторяется.
        let recreated = ComposioIntegrationsViewModel(api: api, cache: cache)
        await recreated.load()
        check(api.catalogRequests == 1, "повторный показ экрана не делает новый запрос")
        check(recreated.loaded && recreated.catalog.map(\.slug) == ["github"], "пересозданный экран показывает каталог")

        // 3. Кнопка «Обновить» — ответ берётся заново, минуя общий кэш.
        await screen.load(force: true)
        check(api.catalogRequests == 2, "принудительное обновление берёт каталог заново")

        // 4. Две загрузки одновременно — один запрос (общий ответ на двоих).
        let parallelAPI = APIClient()
        parallelAPI.holdCatalog = true
        let parallelCache = ComposioCatalogCache(cache: ResponseCache(directory: temporaryDirectory("parallel")), ttl: 60)
        let first = Task { await ComposioIntegrationsViewModel(api: parallelAPI, cache: parallelCache).load() }
        let second = Task { await ComposioIntegrationsViewModel(api: parallelAPI, cache: parallelCache).load() }
        var waited = 0
        while parallelAPI.waitingRequests == 0 && waited < 500 { await Task.yield(); waited += 1 }
        await Task.yield()
        parallelAPI.releaseCatalog()
        await first.value
        await second.value
        check(parallelAPI.catalogRequests == 1, "параллельные экраны склеиваются в один запрос")

        // 5. Устаревший ответ — каталог берут заново.
        let staleAPI = APIClient()
        let staleCache = ComposioCatalogCache(cache: ResponseCache(directory: temporaryDirectory("stale")), ttl: 0)
        let staleScreen = ComposioIntegrationsViewModel(api: staleAPI, cache: staleCache)
        await staleScreen.load()
        await staleScreen.load()
        check(staleAPI.catalogRequests == 2, "устаревший ответ обновляется из сети")

        // 6. После перезапуска приложения прошлый ответ из `ResponseCache`
        //    показывается сразу — не дожидаясь сети.
        let restartCache = ResponseCache(directory: temporaryDirectory("restart"))
        restartCache.store(Data(catalogJSON.utf8), for: ResponseCache.key(path: "/integrations/composio", query: []))
        restartCache.store(Data(rolesJSON.utf8), for: ResponseCache.key(
            path: "/roles",
            query: [URLQueryItem(name: "all", value: "1"), URLQueryItem(name: "projection", value: "list")]
        ))
        let restartAPI = APIClient()
        restartAPI.holdCatalog = true
        let restarted = ComposioIntegrationsViewModel(
            api: restartAPI,
            cache: ComposioCatalogCache(cache: restartCache, ttl: 60)
        )
        let restartLoad = Task { await restarted.load() }
        waited = 0
        while restartAPI.waitingRequests == 0 && waited < 500 { await Task.yield(); waited += 1 }
        check(restarted.loaded, "прошлый ответ показан сразу, без ожидания сети")
        check(restarted.catalog.map(\.slug) == ["gmail"], "каталог из прошлого ответа на экране")
        check(restarted.roles.map(\.id) == ["developer"], "роли из прошлого ответа на экране")
        restartAPI.releaseCatalog()
        await restartLoad.value
        check(restartAPI.catalogRequests == 1, "после прошлого ответа каталог всё равно обновился из сети")

        // 7. Сохранённый доступ не откатывается общим ответом: сервер правку
        //    принял — значит, и общий ответ должен её знать.
        let saveAPI = APIClient()
        let saveCache = ComposioCatalogCache(cache: ResponseCache(directory: temporaryDirectory("save")), ttl: 60)
        let saveScreen = ComposioIntegrationsViewModel(api: saveAPI, cache: saveCache)
        await saveScreen.load()
        check(saveScreen.policies["developer"]?.enabled == true, "доступ роли взят из ответа сервера")
        saveScreen.policies["developer"] = ComposioAccessPolicy(enabled: false, toolkits: nil)
        let saved = await saveScreen.save(toolkit: nil, selected: [])
        check(saved, "доступ роли сохранён")
        let afterSave = ComposioIntegrationsViewModel(api: saveAPI, cache: saveCache)
        await afterSave.load()
        check(saveAPI.catalogRequests == 1, "после сохранения новый экран не делает запрос")
        check(afterSave.policies["developer"]?.enabled == false, "общий ответ знает новый доступ — правка не откатывается")

        print("Composio screen cache: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static let catalogJSON = """
    {"catalog":[{"slug":"gmail","name":"Gmail","logo":null,"description":null,"connected":true,"noAuth":false}],"services":[],"configured":true,"available":true,"roles":[{"role":"developer","enabled":true,"toolkits":null}],"catalogCursor":null,"catalogTotalPages":3,"error":null}
    """

    static let rolesJSON = """
    {"roles":[{"role":"developer","title":"Разработчик","enabled":true}]}
    """

    static func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("composio-cache-\(name)-\(UUID().uuidString)")
    }
}
#endif
