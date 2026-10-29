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
            reconcilePending()
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
            await load()
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
            return true
        } catch {
            self.error = "Не удалось сохранить все изменения. Часть ролей могла сохраниться; повторное нажатие сохранит оставшиеся. \(error.localizedDescription)"
            return false
        }
    }

    /// Подключение сервиса делает тумблер в списке: он сразу уводит
    /// владельца на страницу авторизации Composio.
}

/// Отдельная страница раздела Composio: основные интеграции и вход в полный
/// каталог. В окне «Интеграции» Composio — строка, по которой открывается
/// эта страница.
struct ComposioIntegrationsScreen: View {
    @State private var model = ComposioIntegrationsViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(model: ComposioIntegrationsViewModel? = nil) {
        _model = State(initialValue: model ?? ComposioIntegrationsViewModel())
    }

    var body: some View {
        ScrollView { content.padding(TFSpacing.lg) }
            .background(Color.tfBackground)
            .tfNativeHeader("Composio", displayMode: .inline)
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
                ForEach(model.primarySections) { section in
                    sectionView(section)
                }
                NavigationLink {
                    ComposioCatalogScreen()
                } label: {
                    TFCard(padding: 0) {
                        TFListRow(icon: "square.grid.2x2", iconStyle: .plain, title: "Все интеграции",
                                  subtitle: "полный каталог сервисов Composio",
                                  trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                    }
                }.buttonStyle(TFTapRowStyle()).accessibilityIdentifier("composio.all")
                TFSectionHeader("Доступ к каталогу")
                NavigationLink {
                    ComposioServiceScreen(model: model, toolkit: nil)
                } label: {
                    TFCard(padding: 0) {
                        TFListRow(icon: "square.grid.2x2", iconStyle: .plain, title: "Весь каталог",
                                  subtitle: accessSummary(nil), trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                    }
                }.buttonStyle(TFTapRowStyle()).accessibilityIdentifier("composio.catalog")
            } else if model.loading { TFLoading(.block) }
            TFButton("Обновить", icon: "arrow.clockwise", variant: .secondary, isEnabled: !model.loading && !model.saving) {
                Task { await model.load() }
            }
        }
    }

    /// Раздел основных интеграций: заголовок, что в нём делается и строки
    /// сервисов с тумблером.
    private func sectionView(_ section: ComposioPrimarySection) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader(section.title)
            Text(section.note)
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.toolkits.enumerated()), id: \.element.id) { index, toolkit in
                        if index > 0 { TFDivider(inset: TFSpacing.lg) }
                        ComposioConnectorRow(
                            toolkit: toolkit,
                            isOn: model.isOn(toolkit),
                            isBusy: model.busy.contains(toolkit.slug),
                            destination: AnyView(ComposioServiceScreen(model: model, toolkit: toolkit)),
                            onToggle: { newValue in toggle(toolkit, newValue) }
                        )
                        .accessibilityIdentifier("composio.service.\(toolkit.slug)")
                    }
                }
            }
        }
    }

    private func toggle(_ toolkit: ComposioToolkit, _ isOn: Bool) {
        Task {
            guard let url = await model.setConnected(toolkit, isOn) else { return }
            openURL(url)
        }
    }

    private func accessSummary(_ toolkit: String?) -> String {
        let count = model.selectedRoles(for: toolkit).count
        return count == 0 ? "Роли не выбраны" : count == model.roles.count ? "Все роли" : "Ролей: \(count)"
    }
}

/// Полный каталог сервисов Composio — то, что не вошло в основные разделы.
///
/// Основные интеграции лежат на странице «Composio» (по разделам), здесь
/// весь список: поиск и постраничная догрузка.
struct ComposioCatalogScreen: View {
    @State private var model = ComposioIntegrationsViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView { content.padding(TFSpacing.lg) }
            .background(Color.tfBackground)
            .tfNativeHeader("Все интеграции", displayMode: .inline)
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
            TFTextField("Найти сервис", text: $model.search, icon: "magnifyingglass")
                .onSubmit { Task { await model.searchCatalog() } }
                .accessibilityIdentifier("composio.search")
            TFErrorBanner(model.error, variant: .block)
            if model.loaded {
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(displayCatalog.enumerated()), id: \.element.id) { index, toolkit in
                            if index > 0 { TFDivider(inset: TFSpacing.lg) }
                            ComposioConnectorRow(
                                toolkit: toolkit,
                                isOn: model.isOn(toolkit),
                                isBusy: model.busy.contains(toolkit.slug),
                                destination: AnyView(ComposioServiceScreen(model: model, toolkit: toolkit)),
                                onToggle: { newValue in toggle(toolkit, newValue) }
                            )
                            .accessibilityIdentifier("composio.service.\(toolkit.slug)")
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
        }
    }

    private func toggle(_ toolkit: ComposioToolkit, _ isOn: Bool) {
        Task {
            guard let url = await model.setConnected(toolkit, isOn) else { return }
            openURL(url)
        }
    }

    private var displayCatalog: [ComposioToolkit] {
        model.catalog.sorted { a, b in
            if a.connected != b.connected { return a.connected }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

struct ComposioServiceScreen: View {
    @Bindable var model: ComposioIntegrationsViewModel
    let toolkit: ComposioToolkit?
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
                            HStack(spacing: TFSpacing.md) {
                                ComposioServiceIcon(slug: toolkit.slug)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(toolkit.name)
                                        .tfText(.body)
                                        .foregroundStyle(Color.tfText)
                                        .lineLimit(1)
                                    Text(toolkit.noAuth ? "Авторизация не требуется" : toolkit.connected ? "Общий аккаунт TaskFlow подключён" : "Подключите общий аккаунт TaskFlow")
                                        .tfText(.action)
                                        .foregroundStyle(Color.tfSub)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, TFSpacing.lg)
                            .padding(.vertical, TFSpacing.md)
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
                            Text("Подключение — тумблером в списке сервисов: включили и прошли авторизацию.")
                                .tfText(.caption).foregroundStyle(Color.tfDim)
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

/// Строка коннектора: серая иконка сервиса, название, описание и переключатель.
///
/// Оформление — как у крупных агентов: список коннекторов с иконками, где
/// включение тумблера сразу уводит на авторизацию. Само название — ссылка
/// на экран сервиса (какие роли могут им пользоваться), тумблер — отдельный
/// элемент, поэтому нажатие на него не открывает экран.
private struct ComposioConnectorRow: View {
    let toolkit: ComposioToolkit
    let isOn: Bool
    let isBusy: Bool
    let destination: AnyView
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: TFSpacing.md) {
            NavigationLink(destination: destination) {
                HStack(spacing: TFSpacing.md) {
                    ComposioServiceIcon(slug: toolkit.slug)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toolkit.name)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                            .lineLimit(1)
                        Text(subtitle)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, TFSpacing.lg)
                .padding(.vertical, TFSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(TFTapRowStyle())
            accessory
                .padding(.trailing, TFSpacing.lg)
        }
    }

    private var subtitle: String {
        if let description = toolkit.description, !description.isEmpty { return description }
        return toolkit.noAuth ? "Без авторизации" : "Описание сервиса пока нет"
    }

    @ViewBuilder
    private var accessory: some View {
        if toolkit.noAuth {
            Text("Без авторизации")
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
        } else {
            TFToggle(isOn: Binding(get: { isOn }, set: onToggle))
                .disabled(isBusy)
                .accessibilityLabel(toolkit.name)
        }
    }
}
