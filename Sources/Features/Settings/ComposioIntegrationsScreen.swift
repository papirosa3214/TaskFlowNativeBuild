import SwiftUI
import Observation

struct ComposioWorkspaceRole: Identifiable, Sendable {
    let id: String
    let title: String
    let active: Bool
}

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
    /// Курсор следующей страницы каталога (nil — страниц больше нет).
    var catalogCursor: String?
    /// Сколько страниц в каталоге всего.
    var catalogTotalPages: Int?
    var loadingMore = false
    private let api = APIClient()
    private(set) var loaded = false

    private let testFixture: Bool
    init(testFixture: Bool = false) { self.testFixture = testFixture }

    var fixture: Bool {
        #if DEBUG
        testFixture
        #else
        false
        #endif
    }

    func load() async {
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
        do {
            let profiles = try await api.rolesList(all: true)
            let overview = try await api.composioConnections()
            roles = profiles.map { ComposioWorkspaceRole(id: $0.role, title: $0.title, active: $0.isEnabled) }
            let access = Dictionary((overview.roles ?? []).map { ($0.role, $0) }, uniquingKeysWith: { _, latest in latest })
            policies = Dictionary(uniqueKeysWithValues: roles.map { role in
                (role.id, ComposioAccessPolicy(enabled: access[role.id]?.enabled ?? false, toolkits: access[role.id]?.toolkits))
            })
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
        } catch { self.error = error.localizedDescription }
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
            return true
        } catch {
            self.error = "Не удалось сохранить все изменения. Часть ролей могла сохраниться; повторное нажатие сохранит оставшиеся. \(error.localizedDescription)"
            return false
        }
    }

    func connect(_ toolkit: String) async -> URL? {
        guard let role = roles.first, !loading, !saving, !fixture else { return nil }
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await api.authorizeRoleComposio(role: role.id, toolkit: toolkit)
            guard let url = URL(string: result.url), url.scheme == "https" else {
                error = "Сервис не вернул ссылку подключения"; return nil
            }
            awaitingAuthorization = true
            return url
        } catch { self.error = error.localizedDescription; return nil }
    }
}

struct ComposioIntegrationsScreen: View {
    @State private var model = ComposioIntegrationsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    let embedded: Bool
    init(embedded: Bool = false, model: ComposioIntegrationsViewModel? = nil) {
        self.embedded = embedded
        _model = State(initialValue: model ?? ComposioIntegrationsViewModel())
    }

    var body: some View {
        Group {
            if embedded { content }
            else {
                ScrollView { content.padding(TFSpacing.lg) }
                    .background(Color.tfBackground)
                    .tfNativeHeader("Composio", displayMode: .inline)
            }
        }
        .task { if !model.loaded { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && model.awaitingAuthorization {
                model.awaitingAuthorization = false
                Task { await model.load() }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            TFCard(padding: 0) {
                TFListRow(icon: "puzzlepiece.extension", iconStyle: .asset("IntegrationComposio"), title: "Composio",
                          subtitle: model.loading ? "Проверяем подключение…" : model.available ? "В сети" : "Подключение недоступно",
                          trailing: AnyView(Image(systemName: model.available ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(model.available ? Color.tfTeal : Color.tfSub)))
            }
            Text("Подключайте аккаунты один раз и выбирайте, какие роли смогут ими пользоваться.")
                .tfText(.action).foregroundStyle(Color.tfSub)
            TFErrorBanner(model.error, variant: .block)
            if model.loaded {
                TFSectionHeader("Доступ к каталогу")
                NavigationLink {
                    ComposioServiceScreen(model: model, toolkit: nil)
                } label: {
                    TFCard(padding: 0) {
                        TFListRow(icon: "square.grid.2x2", iconStyle: .plain, title: "Весь каталог",
                                  subtitle: accessSummary(nil), trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                    }
                }.buttonStyle(TFTapRowStyle()).accessibilityIdentifier("composio.catalog")
                TFSectionHeader("Сервисы")
                TFTextField("Найти сервис", text: $model.search, icon: "magnifyingglass")
                    .onSubmit { Task { await model.searchCatalog() } }
                    .accessibilityIdentifier("composio.search")
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(displayCatalog.enumerated()), id: \.element.id) { index, toolkit in
                            if index > 0 { TFDivider(inset: TFSpacing.lg) }
                            NavigationLink {
                                ComposioServiceScreen(model: model, toolkit: toolkit)
                            } label: {
                                TFListRow(icon: "link", iconStyle: .remote(toolkit.logo), title: toolkit.name,
                                          subtitle: toolkit.description ?? "\(toolkit.noAuth ? "Без авторизации" : toolkit.connected ? "Подключён" : "Не подключён") · \(model.selectedRoles(for: toolkit.slug).count) ролей",
                                          trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                            }.buttonStyle(TFTapRowStyle()).accessibilityIdentifier("composio.service.\(toolkit.slug)")
                        }
                    }
                }
                if displayCatalog.isEmpty { TFEmptyState(text: "Сервисы не найдены", description: "Попробуйте другое название.") }
                if model.catalogCursor != nil {
                    TFButton(model.loadingMore ? "Загружаем…" : "Показать ещё", icon: "arrow.down", variant: .secondary, isEnabled: !model.loading && !model.loadingMore) {
                        Task { await model.loadMoreCatalog() }
                    }
                    .accessibilityIdentifier("composio.loadMore")
                    if let pages = model.catalogTotalPages {
                        Text("Показана часть каталога — всего страниц: \(pages).")
                            .tfText(.caption).foregroundStyle(Color.tfDim)
                    }
                }
            } else if model.loading { TFLoading(.block) }
            TFButton("Обновить", icon: "arrow.clockwise", variant: .secondary, isEnabled: !model.loading && !model.saving) {
                Task { await model.load() }
            }
        }
    }

    private var displayCatalog: [ComposioToolkit] {
        model.catalog.sorted { a, b in
            if a.connected != b.connected { return a.connected }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func accessSummary(_ toolkit: String?) -> String {
        let count = model.selectedRoles(for: toolkit).count
        return count == 0 ? "Роли не выбраны" : count == model.roles.count ? "Все роли" : "Ролей: \(count)"
    }
}

struct ComposioServiceScreen: View {
    @Bindable var model: ComposioIntegrationsViewModel
    let toolkit: ComposioToolkit?
    @Environment(\.openURL) private var openURL
    @State private var selected = Set<String>()
    @State private var baseline = Set<String>()
    @State private var saved = false

    private var slug: String? { toolkit?.slug }
    private var currentToolkit: ComposioToolkit? { model.catalog.first { $0.slug == slug } ?? toolkit }
    private var lockedRoles: Set<String> {
        guard toolkit != nil else { return [] }
        return model.selectedRoles(for: nil)
    }

    var body: some View {
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.lg) {
                    if let toolkit = currentToolkit {
                        TFCard(padding: 0) {
                            TFListRow(icon: "link", iconStyle: .remote(toolkit.logo), title: toolkit.name,
                                      subtitle: toolkit.noAuth ? "Авторизация не требуется" : toolkit.connected ? "Общий аккаунт TaskFlow подключён" : "Подключите общий аккаунт TaskFlow")
                        }
                        if toolkit.name == "GitHub MCP" {
                            Text("Это отдельный сервис. Для обычного подключения аккаунта выберите «GitHub» в каталоге.")
                                .tfText(.action).foregroundStyle(Color.tfSub)
                        }
                        if let description = toolkit.description {
                            Text(description)
                                .tfText(.action).foregroundStyle(Color.tfSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !toolkit.connected && !toolkit.noAuth {
                            TFButton("Подключить аккаунт", icon: "link", variant: .secondary, isEnabled: !model.loading && !model.saving) {
                                Task { if let url = await model.connect(toolkit.slug) { openURL(url) } }
                            }.accessibilityIdentifier("composio.connect")
                        }
                    } else {
                        Text("Выбранные роли получат доступ ко всем сервисам каталога через общие аккаунты TaskFlow.")
                            .tfText(.action).foregroundStyle(Color.tfSub)
                    }
                    TFSectionHeader("Кого подключить")
                    TFCard(padding: 0) {
                        VStack(spacing: 0) {
                            selectionRow("Все роли", checked: selected.count == model.roles.count) {
                                selected = Set(model.roles.map(\.id)); saved = false
                            }.accessibilityIdentifier("composio.roles.all")
                            TFDivider(inset: TFSpacing.lg)
                            selectionRow("Выбрать роли", checked: selected.count != model.roles.count) {
                                if selected.count == model.roles.count { selected = lockedRoles }
                                saved = false
                            }.accessibilityIdentifier("composio.roles.choose")
                        }
                    }
                    TFCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.roles.enumerated()), id: \.element.id) { index, role in
                                if index > 0 { TFDivider(inset: TFSpacing.lg) }
                                TFListRow(icon: "person", iconStyle: .plain, title: role.title,
                                          subtitle: lockedRoles.contains(role.id) ? "Доступ через весь каталог" : role.active ? nil : "Роль отключена",
                                          trailing: AnyView(Image(systemName: selected.contains(role.id) ? "checkmark.square.fill" : "square").foregroundStyle(selected.contains(role.id) ? Color.tfText : Color.tfDim)),
                                          action: {
                                              if selected.contains(role.id) { selected.remove(role.id) } else { selected.insert(role.id) }
                                              saved = false
                                          })
                                    .disabled(lockedRoles.contains(role.id) || model.saving || model.loading)
                                    .accessibilityValue(selected.contains(role.id) ? "Выбрана" : "Не выбрана")
                                    .accessibilityIdentifier("composio.role.\(role.id)")
                            }
                        }
                    }
                    if !lockedRoles.isEmpty {
                        Text("Роли с доступом ко всему каталогу уже подключены. Изменить их доступ можно в разделе «Весь каталог».")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                    }
                    Text("В планировании роли могут только читать. Аккаунт и выбор ролей сохраняются отдельно.")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                    TFErrorBanner(model.error, variant: .block)
                    if saved { Text("Выбор ролей сохранён").tfText(.action).foregroundStyle(Color.tfSub).accessibilityIdentifier("composio.saved") }
                }.padding(TFSpacing.lg)
            }
        }
        .tfNativeHeader(toolkit?.name ?? "Весь каталог", displayMode: .inline)
        .safeAreaInset(edge: .bottom) {
            TFButton(model.saving ? "Сохраняем…" : "Сохранить", icon: "checkmark",
                     isEnabled: !model.loading && !model.saving && selected != baseline) {
                Task {
                    if await model.save(toolkit: slug, selected: selected) { baseline = selected; saved = true }
                }
            }.accessibilityIdentifier("composio.save")
                .padding(TFSpacing.lg).background(Color.tfBackground)
        }
        .onAppear { selected = model.selectedRoles(for: slug); baseline = selected }
    }

    private func selectionRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        TFListRow(icon: title == "Все роли" ? "person.2" : "person.crop.rectangle", iconStyle: .plain,
                  title: title, trailing: AnyView(Image(systemName: checked ? "largecircle.fill.circle" : "circle").foregroundStyle(checked ? Color.tfText : Color.tfDim)), action: action)
            .disabled(model.saving || model.loading)
    }
}
