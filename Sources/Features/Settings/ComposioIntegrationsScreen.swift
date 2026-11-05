import SwiftUI
import Observation

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
            .tfScreenBackground()
            .tfNativeHeader("Composio", displayMode: .inline)
            .task { if !model.loaded { await model.load() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && model.awaitingAuthorization {
                    model.awaitingAuthorization = false
                    // Сервис подключили в браузере — каталог берём заново.
                    Task { await model.load(force: true) }
                }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            TFCard(padding: 0, bordered: true) {
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
                    TFCard(padding: 0, bordered: true) {
                        TFListRow(icon: "square.grid.2x2", iconStyle: .plain, title: "Все интеграции",
                                  subtitle: "полный каталог сервисов Composio",
                                  trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                    }
                }.buttonStyle(TFTapRowStyle()).accessibilityIdentifier("composio.all")
                TFSectionHeader("Доступ к каталогу")
                NavigationLink {
                    ComposioServiceScreen(model: model, toolkit: nil)
                } label: {
                    TFCard(padding: 0, bordered: true) {
                        TFListRow(icon: "square.grid.2x2", iconStyle: .plain, title: "Весь каталог",
                                  subtitle: accessSummary(nil), trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                    }
                }.buttonStyle(TFTapRowStyle()).accessibilityIdentifier("composio.catalog")
            } else if model.loading { TFLoading(.block) }
            TFButton("Обновить", icon: "arrow.clockwise", variant: .secondary, isEnabled: !model.loading && !model.saving) {
                // Кнопка обновления — общий кэш обходим: владелец просил
                // свежий каталог.
                Task { await model.load(force: true) }
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
            TFCard(padding: 0, bordered: true) {
                // LazyVStack: рисуются только видимые строки, а не весь
                // раздел разом.
                LazyVStack(spacing: 0) {
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
            .tfScreenBackground()
            .tfNativeHeader("Все интеграции", displayMode: .inline)
            .task { if !model.loaded { await model.load() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && model.awaitingAuthorization {
                    model.awaitingAuthorization = false
                    // Сервис подключили в браузере — каталог берём заново.
                    Task { await model.load(force: true) }
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
                TFCard(padding: 0, bordered: true) {
                    // LazyVStack: в каталоге до 1600 строк, рисуются только
                    // видимые.
                    LazyVStack(spacing: 0) {
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
            TFScreenFill()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.lg) {
                    if let toolkit = currentToolkit {
                        TFCard(padding: 0, bordered: true) {
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
                    TFCard(padding: 0, bordered: true) {
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
                    TFCard(padding: 0, bordered: true) {
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
                .padding(TFSpacing.lg).tfScreenBackground()
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
