import Foundation
import Observation

/// Роль рабочего пространства в экране Composio.
struct ComposioWorkspaceRole: Identifiable, Sendable {
    let id: String
    let title: String
    let active: Bool
}

/// Модель экранов Composio: каталог сервисов, роли и доступ ролей к
/// сервисам.
///
/// Отдельный `@Observable`-объект без SwiftUI в самой модели — так же, как
/// остальные вью-модели приложения (`RoutinesViewModel`, `TaskFormViewModel`).
@MainActor @Observable
final class ComposioIntegrationsViewModel {
    var roles: [ComposioWorkspaceRole] = []
    var policies: [String: ComposioAccessPolicy] = [:]
    var catalog: [ComposioToolkit] = []
    var connections: [RoleIntegrationToolkit] = []
    var configured = false
    var available = false
    var loading = false
    var saving = false
    var error: String?
    var search = ""
    var awaitingAuthorization = false
    /// Сервисы, у которых тумблер меняется прямо сейчас: slug → новое
    /// состояние (показываем его, а не серверное, чтобы переключатель не
    /// отпрыгивал назад во время авторизации).
    private(set) var toggles = ComposioToggleState()
    /// Сервисы, для которых сейчас идёт запрос к серверу.
    private(set) var busy: Set<String> = []
    /// Курсор следующей страницы каталога (nil — страниц больше нет).
    var catalogCursor: String?
    /// Сколько страниц в каталоге всего.
    var catalogTotalPages: Int?
    var loadingMore = false
    private let api: APIClient
    /// Общий кэш каталога: ответ один на все экраны, и пока он свежий, сеть
    /// не трогается (30.10.2026).
    private let cache: ComposioCatalogCache
    private(set) var loaded = false

    private let testFixture: Bool
    init(api: APIClient = APIClient(), cache: ComposioCatalogCache = .shared, testFixture: Bool = false) {
        self.api = api
        self.cache = cache
        self.testFixture = testFixture
    }

    var fixture: Bool {
        #if DEBUG
        testFixture
        #else
        false
        #endif
    }

    /// Загрузить каталог.
    ///
    /// `force` — взять ответ заново, минуя общий кэш: после правки
    /// (кнопка «Обновить», подключение сервиса, возврат из браузера с
    /// авторизацией). Без него берётся общий ответ: пока он свежий, сеть не
    /// трогается, а прошлый ответ показывается сразу, не дожидаясь сети.
    func load(force: Bool = false) async {
        guard !loading, !saving else { return }
        loading = true
        error = nil
        defer { loading = false }
        if fixture {
            roles = [ComposioWorkspaceRole(id: "secretary", title: "Помощник владельца", active: true),
                     ComposioWorkspaceRole(id: "developer", title: "Разработчик", active: true),
                     ComposioWorkspaceRole(id: "reviewer", title: "Ревьюер", active: true)]
            policies = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, ComposioAccessPolicy(enabled: false, toolkits: nil)) })
            catalog = [ComposioToolkit(slug: "linear", name: "Linear", logo: nil, description: nil, connected: true, noAuth: false),
                       ComposioToolkit(slug: "github", name: "GitHub", logo: nil, description: nil, connected: false, noAuth: false),
                       ComposioToolkit(slug: "notion", name: "Notion", logo: nil, description: nil, connected: false, noAuth: false)]
            configured = true; available = true; loaded = true
            catalogCursor = nil; catalogTotalPages = nil
            return
        }
        // Прошлый ответ — сразу на экран: каталог из общего кэша, без
        // ожидания сети (после перезапуска приложения — из `ResponseCache`).
        if let previous = await cache.previous() {
            apply(previous)
        }
        do {
            // Свежий ответ — из общего кэша: экраны делят один ответ и не
            // делают новый запрос, пока он не устарел.
            let api = self.api
            let snapshot = try await cache.snapshot(force: force) {
                async let profiles = api.rolesList(all: true)
                async let overview = api.composioConnections()
                let roles = try await profiles
                let data = try await overview
                return ComposioCatalogSnapshot(
                    roles: roles,
                    overview: data,
                    policies: ComposioCatalogSnapshot.policies(from: data, roles: roles)
                )
            }
            apply(snapshot)
            reconcilePending()
        } catch { self.error = error.localizedDescription }
    }

    /// Разложить снимок по полям экрана.
    private func apply(_ snapshot: ComposioCatalogSnapshot) {
        let overview = snapshot.overview
        roles = snapshot.roles.map { ComposioWorkspaceRole(id: $0.role, title: $0.title, active: $0.isEnabled) }
        policies = snapshot.policies
        configured = overview.configured ?? false
        available = overview.available ?? false
        catalog = overview.catalog
        for service in overview.services where !catalog.contains(where: { $0.slug == service.slug }) {
            catalog.append(ComposioToolkit(slug: service.slug, name: service.name ?? service.slug, logo: service.logo, description: service.description, connected: service.connected ?? false, noAuth: false))
        }
        connections = overview.connectedServices
        catalogCursor = overview.catalogCursor
        catalogTotalPages = overview.catalogTotalPages
        error = overview.error
        loaded = true
    }

    func searchCatalog() async {
        guard let role = roles.first, !loading, !saving else { return }
        if fixture { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await api.roleComposio(role: role.id, search: search)
            catalog = result.catalog
            catalogCursor = result.catalogCursor
            catalogTotalPages = result.catalogTotalPages
            available = result.available
            error = result.error
        } catch { self.error = error.localizedDescription }
    }

    /// Догрузить следующую страницу каталога: сервисов больше тысячи, на
    /// экране помещается строка за раз — список листается постранично.
    func loadMoreCatalog() async {
        guard let role = roles.first, let cursor = catalogCursor, !loading, !saving, !loadingMore else { return }
        if fixture { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let result = try await api.roleComposio(role: role.id, search: search, cursor: cursor)
            var merged = catalog
            var seen = Set(catalog.map(\.slug))
            for toolkit in result.catalog where !seen.contains(toolkit.slug) {
                seen.insert(toolkit.slug)
                merged.append(toolkit)
            }
            catalog = merged
            catalogCursor = result.catalogCursor
            catalogTotalPages = result.catalogTotalPages
            error = result.error
        } catch { self.error = error.localizedDescription }
    }

    func selectedRoles(for toolkit: String?) -> Set<String> {
        Set(roles.filter { policies[$0.id]?.allows(toolkit) == true }.map(\.id))
    }

    /// Основные интеграции — по разделам: подключённые и знаковые сервисы.
    /// Остальные живут на экране «Все интеграции».
    var primarySections: [ComposioPrimarySection] {
        ComposioPrimaryServices.sections(from: catalog)
    }

    /// Состояние тумблера сервиса: пока идёт подключение, показываем то,
    /// на что владелец нажал, — иначе переключатель отпрыгивает назад.
    func isOn(_ toolkit: ComposioToolkit) -> Bool {
        toggles.isOn(toolkit.slug, connected: toolkit.connected)
    }

    /// Включение сервиса уводит владельца на страницу авторизации Composio:
    /// ссылку отдаёт сервер, дальше — браузер. Выключение отключает
    /// подключённые аккаунты сервиса.
    /// Возвращает ссылку авторизации, если её удалось получить.
    func setConnected(_ toolkit: ComposioToolkit, _ isOn: Bool) async -> URL? {
        guard !busy.contains(toolkit.slug), !saving else { return nil }
        busy.insert(toolkit.slug)
        toggles.begin(toolkit.slug, isOn: isOn)
        defer { busy.remove(toolkit.slug) }
        do {
            if isOn {
                let authorization = try await api.composioLinkAccount(toolkit: toolkit.slug)
                guard let url = URL(string: authorization.url), url.scheme == "https" else {
                    toggles.cancel(toolkit.slug)
                    error = "Сервис не вернул ссылку подключения"
                    return nil
                }
                // Пока владелец ходит в браузере, тумблер остаётся включённым:
                // состояние снимется, когда каталог вернёт «подключено».
                awaitingAuthorization = true
                return url
            }
            let accounts = try await api.composioAccounts(toolkit: toolkit.slug)
            for account in accounts {
                try await api.composioDeleteAccount(toolkit: toolkit.slug, id: account.id)
            }
            // Каталог изменился — общий ответ надо взять заново.
            await load(force: true)
            toggles.cancel(toolkit.slug)
            return nil
        } catch {
            toggles.cancel(toolkit.slug)
            self.error = error.localizedDescription
            return nil
        }
    }

    /// После ответа сервера сверяем тумблеры с каталогом: если сервис уже в
    /// нужном состоянии, ожидание заканчивается.
    private func reconcilePending() {
        var connected: [String: Bool] = [:]
        for toolkit in catalog { connected[toolkit.slug] = toolkit.connected }
        toggles.reconcile(connected: connected)
    }

    func save(toolkit: String?, selected: Set<String>) async -> Bool {
        guard loaded, !loading, !saving else { return false }
        saving = true; error = nil
        defer { saving = false }
        do {
            // Validate every change before issuing any mutation.
            let changes = try roles.compactMap { role -> (String, ComposioAccessPolicy)? in
                guard let current = policies[role.id] else { return nil }
                let allowed = selected.contains(role.id)
                guard current.allows(toolkit) != allowed else { return nil }
                return (role.id, try current.changing(toolkit, allowed: allowed))
            }
            for (id, policy) in changes {
                if !fixture { try await api.saveRoleComposio(role: id, enabled: policy.enabled, toolkits: policy.toolkits) }
                // Preserve successful writes if a later role fails; retry only remaining changes.
                policies[id] = policy
            }
            // Общий ответ обновляем на месте: сервер правку принял, а общий
            // кэш — нет, и следующий экран вернул бы прежнее состояние.
            await cache.updatePolicies(policies)
            return true
        } catch {
            self.error = "Не удалось сохранить все изменения. Часть ролей могла сохраниться; повторное нажатие сохранит оставшиеся. \(error.localizedDescription)"
            return false
        }
    }

    /// Подключение сервиса делает тумблер в списке: он сразу уводит
    /// владельца на страницу авторизации Composio.
}
