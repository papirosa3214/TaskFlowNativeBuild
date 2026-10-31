import SwiftUI
import EventKit
import Observation

/// Вью-модель `IntegrationsScreen` — статус Google (сервер), права/списки
/// Apple (`EventKit`, устройство). Контракты — `APIClient+GoogleIntegrations.swift`/
/// `AppleEventKitAccess.swift`, поведение — `src/screens/IntegrationsScreen.tsx`
/// (спека §14 не даёт нужной детали, ARCHITECTURE.md п.3 разрешает читать код).
@MainActor
@Observable
final class IntegrationsViewModel {
    private let apiClient = APIClient()

    var status: IntegrationStatusResponse?
    var isStatusLoading = true
    var webhooks: [TaskFlowWebhook]?
    var isWebhookStatusLoading = true
    var googleLists: [GoogleTaskListItem] = []
    var isGoogleListsLoading = false
    var googleCalendars: [GoogleCalendarInfo] = []
    var isGoogleCalendarsLoading = false

    var calPermGranted = AppleEventKitAccess.calendarGranted()
    var remPermGranted = AppleEventKitAccess.remindersGranted()
    var appleCalendars: [EKCalendar] = []
    var appleReminderLists: [EKCalendar] = []
    var selectedAppleCalendarIds: Set<String> = Set(IntegrationsLocalPrefs.appleCalendarIds())
    var selectedGoogleCalendarIds: Set<String> = Set(IntegrationsLocalPrefs.googleCalendarIds())
    var selectedReminderListId: String? = IntegrationsLocalPrefs.reminderListId()

    var isGoogleAuthorizing = false
    var isGoogleSyncing = false
    var isGoogleDisconnecting = false
    var isAppleSyncing = false
    var isThingsSyncing = false
    var thingsBridgeAvailable = false

    var errorMessage: String?
    var successMessage: String?

    var googleConnected: Bool { status?.google.connected ?? false }

    enum WebhookStatus: Equatable {
        case loading, unavailable, none, disabled, failed, active(Int)
    }

    var webhookStatus: WebhookStatus {
        if isWebhookStatusLoading { return .loading }
        guard let webhooks else { return .unavailable }
        guard !webhooks.isEmpty else { return .none }
        let enabled = webhooks.filter(\.enabled)
        guard !enabled.isEmpty else { return .disabled }
        if enabled.contains(where: { $0.lastError != nil || ($0.lastDeliveryStatus ?? 0) >= 400 }) {
            return .failed
        }
        return .active(enabled.count)
    }

    func loadWebhookStatus() async {
        isWebhookStatusLoading = true
        defer { isWebhookStatusLoading = false }
        webhooks = try? await apiClient.webhooks()
    }

    func updateWebhookStatus(_ webhooks: [TaskFlowWebhook]?) {
        self.webhooks = webhooks
        isWebhookStatusLoading = false
    }

    func loadThingsBridge() async {
        thingsBridgeAvailable = (try? await ThingsBridgeAPI.shared.health()) == true
    }

    func syncThings(taskStore: TaskStore, projectStore: ProjectStore) async {
        errorMessage = nil
        isThingsSyncing = true
        defer { isThingsSyncing = false }
        do {
            let result = try await ThingsBridgeAPI.shared.sync()
            await taskStore.load(silent: true)
            await projectStore.load()
            thingsBridgeAvailable = true
            successMessage = "Things: импортировано \(result.imported), отправлено \(result.exported), обновлено \(result.updated)"
            scheduleSuccessClear()
        } catch {
            thingsBridgeAvailable = false
            errorMessage = "Ошибка синхронизации Things: \(Self.message(error))"
        }
    }

    func loadAppleState() {
        calPermGranted = AppleEventKitAccess.calendarGranted()
        remPermGranted = AppleEventKitAccess.remindersGranted()
        if calPermGranted { appleCalendars = AppleEventKitAccess.calendars() }
        if remPermGranted {
            appleReminderLists = AppleEventKitAccess.reminderLists()
            if selectedReminderListId == nil, let first = defaultReminderList(appleReminderLists) {
                selectedReminderListId = first.calendarIdentifier
                IntegrationsLocalPrefs.setReminderListId(first.calendarIdentifier)
            }
        }
    }

    private func defaultReminderList(_ lists: [EKCalendar]) -> EKCalendar? {
        lists.first { $0.calendarIdentifier == AppleEventKitAccess.store.defaultCalendarForNewReminders()?.calendarIdentifier } ?? lists.first
    }

    func loadGoogleStatus() async {
        // Прошлый статус из кэша — виден сразу, сеть его обновит.
        if status == nil { status = apiClient.cachedIntegrationsStatus() }
        isStatusLoading = true
        defer { isStatusLoading = false }
        do {
            status = try await apiClient.integrationsStatus()
        } catch {
            // Молчаливо: статус недоступен — секции покажут «Проверка…»/«Импорт задач»,
            // отдельного баннера под это в вебе тоже нет.
        }
        await loadGoogleListsIfNeeded()
        await loadGoogleCalendarsIfNeeded()
    }

    func loadGoogleListsIfNeeded() async {
        guard googleConnected else { return }
        isGoogleListsLoading = true
        defer { isGoogleListsLoading = false }
        googleLists = (try? await apiClient.googleTaskLists()) ?? []
    }

    func loadGoogleCalendarsIfNeeded() async {
        guard googleConnected else { return }
        isGoogleCalendarsLoading = true
        defer { isGoogleCalendarsLoading = false }
        googleCalendars = (try? await apiClient.googleCalendars()) ?? []
    }

    // MARK: - Apple Календарь

    func requestCalendarAccess() async {
        errorMessage = nil
        let granted = await AppleEventKitAccess.requestCalendarAccess()
        calPermGranted = AppleEventKitAccess.calendarGranted()
        if granted {
            appleCalendars = AppleEventKitAccess.calendars()
            let allIds = Set(appleCalendars.map(\.calendarIdentifier))
            selectedAppleCalendarIds = allIds
            IntegrationsLocalPrefs.setAppleCalendarIds(Array(allIds))
        } else if !calPermGranted {
            errorMessage = "Доступ к Apple Календарю не выдан. Проверьте разрешение в Настройках iPhone."
        }
    }

    func toggleAppleCalendar(_ id: String) {
        if selectedAppleCalendarIds.contains(id) {
            selectedAppleCalendarIds.remove(id)
        } else {
            selectedAppleCalendarIds.insert(id)
        }
        IntegrationsLocalPrefs.setAppleCalendarIds(Array(selectedAppleCalendarIds))
    }

    // MARK: - Apple Напоминания

    func requestRemindersAccess() async {
        errorMessage = nil
        let granted = await AppleEventKitAccess.requestRemindersAccess()
        remPermGranted = AppleEventKitAccess.remindersGranted()
        if granted {
            appleReminderLists = AppleEventKitAccess.reminderLists()
            if let first = defaultReminderList(appleReminderLists) {
                selectedReminderListId = first.calendarIdentifier
                IntegrationsLocalPrefs.setReminderListId(first.calendarIdentifier)
            }
        } else if !remPermGranted {
            errorMessage = "Доступ к Apple Напоминаниям не выдан. Проверьте разрешение в Настройках iPhone."
        }
    }

    func selectReminderList(_ id: String) {
        selectedReminderListId = id
        IntegrationsLocalPrefs.setReminderListId(id)
    }

    func syncAppleReminders(taskStore: TaskStore, projectStore: ProjectStore) async {
        errorMessage = nil
        isAppleSyncing = true
        defer { isAppleSyncing = false }

        var appleProjectId = projectStore.projects.first { $0.name == "Apple Напоминания" }?.id
        if appleProjectId == nil {
            appleProjectId = await projectStore.create(name: "Apple Напоминания", color: "#FF9500")?.id
        }

        let list = appleReminderLists.first { $0.calendarIdentifier == selectedReminderListId }
        let result = await AppleRemindersSync.syncAll(
            tasks: taskStore.tasks, list: list, taskStore: taskStore, defaultProjectId: appleProjectId
        )
        successMessage = "Синхронизация Apple Напоминаний: добавлено в TaskFlow: \(result.imported), отправлено в Apple: \(result.exported), обновлено: \(result.updated)"
        scheduleSuccessClear()
    }

    // MARK: - Google

    func toggleGoogleCalendar(_ id: String) {
        if selectedGoogleCalendarIds.contains(id) {
            selectedGoogleCalendarIds.remove(id)
        } else {
            selectedGoogleCalendarIds.insert(id)
        }
        IntegrationsLocalPrefs.setGoogleCalendarIds(Array(selectedGoogleCalendarIds))
    }

    func connectGoogle() async {
        errorMessage = nil
        isGoogleAuthorizing = true
        defer { isGoogleAuthorizing = false }
        do {
            let authURL = try await apiClient.googleAuthURL(redirectURI: GoogleOAuth.redirectURI)
            guard let url = URL(string: authURL.url) else { throw APIError.invalidResponse }
            let code = try await GoogleOAuth.authorize(url: url)
            let result = try await apiClient.googleCallback(code: code, redirectURI: GoogleOAuth.redirectURI)
            successMessage = "Google аккаунт \(result.email ?? "") успешно подключён!"
            scheduleSuccessClear()
            await loadGoogleStatus()
        } catch is CancellationError {
            // Пользователь закрыл окно входа — не ошибка.
        } catch {
            errorMessage = "Ошибка подключения Google: \(Self.message(error))"
        }
    }

    func disconnectGoogle() async {
        errorMessage = nil
        isGoogleDisconnecting = true
        defer { isGoogleDisconnecting = false }
        do {
            _ = try await apiClient.googleDisconnect()
            await loadGoogleStatus()
        } catch {
            errorMessage = "Ошибка отключения Google: \(Self.message(error))"
        }
    }

    func syncGoogle() async {
        errorMessage = nil
        isGoogleSyncing = true
        defer { isGoogleSyncing = false }
        do {
            let listId = status?.google.settings.listId ?? "@default"
            let result = try await apiClient.googleSync(listId: listId)
            successMessage = "Google Задачи: импортировано \(result.imported), обновлено \(result.updated) (всего \(result.totalGoogleTasks))"
            scheduleSuccessClear()
            await loadGoogleStatus()
        } catch {
            errorMessage = "Ошибка синхронизации Google: \(Self.message(error))"
        }
    }

    func selectGoogleList(_ id: String) async {
        _ = try? await apiClient.updateGoogleListId(id)
        await loadGoogleStatus()
    }

    private func scheduleSuccessClear() {
        let current = successMessage
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if successMessage == current { successMessage = nil }
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

/// `/settings/integrations` — spec/SCREENS-2.md §14. В одной точке собраны
/// TaskFlow webhooks, Linear/Gmail, Apple Календарь/Напоминания (`EventKit`),
/// Things и Google Задачи/Календарь (`APIClient+GoogleIntegrations.swift`).
///
/// ⚠️ Живой сервер — только чтение (граница задачи): код ниже реализует
/// подключение/синхронизацию/отключение по-настоящему (иначе владелец не
/// сможет ими пользоваться), но при проверке этой задачи ни одна из
/// мутирующих кнопок не нажималась — только компиляция и сверка со спекой/
/// скриншотом (см. отчёт).
struct IntegrationsScreen: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore

    @State private var viewModel = IntegrationsViewModel()
    @State private var isLinearOpen = false
    @State private var isGmailOpen = false
    @State private var composio = ComposioIntegrationsViewModel()
    @State private var isAppleCalOpen = false
    @State private var isAppleRemOpen = false
    @State private var isThingsOpen = false
    @State private var externalApps = ExternalAppAccessStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isGoogleTasksOpen = false // веб-дефолт: этот аккордеон открыт сразу
    @State private var isGoogleCalOpen = false

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: TFSpacing.xl) {
                        TFErrorBanner(viewModel.errorMessage, variant: .block)
                        if let successMessage = viewModel.successMessage {
                            successBanner(successMessage)
                        }
                        integrationGroup("Подключения TaskFlow") {
                            NavigationLink {
                                WebhooksScreen(onStatusUpdate: viewModel.updateWebhookStatus)
                            } label: {
                                TFListRow(
                                    icon: "arrow.triangle.branch",
                                    iconStyle: .plain,
                                    title: "Вебхуки",
                                    subtitle: "События TaskFlow → внешний сервис",
                                    trailing: AnyView(webhookAccessory),
                                    titleStyle: .action,
                                    verticalPadding: TFSpacing.xs
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("integrations.webhooks")
                            .hintAnchor(HintAnchorID.webhooksEntry)
                            TFDivider(inset: dividerInset)
                            IntegrationAccordionCard(icon: "arrow.down.doc", asset: "IntegrationLinear", title: "Linear", subtitle: "Выбор задач и перенос структуры", badge: nil, isExpanded: $isLinearOpen, identifier: "integrations.linear") {
                                LinearImportScreen(embedded: true)
                            }
                            IntegrationAccordionCard(icon: "envelope", title: "Gmail", subtitle: externalApps.gmailDetail, badge: externalApps.gmailStatus, badgeColor: externalApps.accounts.contains(where: \.connected) ? .tfTeal : .tfSub, isExpanded: $isGmailOpen, identifier: "integrations.gmail") {
                                GmailIntegrationCard()
                            }
                            ForEach(composio.connections.filter { !["gmail", "linear"].contains($0.slug) }) { service in
                                TFDivider(inset: dividerInset)
                                NavigationLink {
                                    ComposioServiceScreen(model: composio, toolkit: ComposioToolkit(slug: service.slug, name: service.name ?? service.slug, logo: service.logo, description: service.description, connected: true, noAuth: false))
                                } label: {
                                    TFListRow(icon: "link", iconStyle: .bundledLogo(service.slug), title: service.name ?? service.slug, subtitle: "Подключение TaskFlow", trailing: AnyView(Text("Подключено").tfText(.meta).foregroundStyle(Color.tfTeal)), titleStyle: .action, verticalPadding: TFSpacing.xs)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("integrations.connected.\(service.slug)")
                            }
                            TFDivider(inset: dividerInset)
                            NavigationLink {
                                ComposioIntegrationsScreen()
                            } label: {
                                TFListRow(icon: "puzzlepiece.extension", iconStyle: .asset("IntegrationComposio"), title: "Composio", subtitle: "Основные интеграции и каталог сервисов", trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)), titleStyle: .action, verticalPadding: TFSpacing.xs)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("integrations.composio")

                        }
                        appleSection
                        thingsSection
                        googleSection
                    }
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.top, TFSpacing.sm)
                    .padding(.bottom, TFSpacing.xl * 2)
                }
            }
        }
        .tfNativeHeader("Интеграции")
        .onChange(of: scenePhase) { _, phase in
            // Возврат в приложение — каталог Composio берём заново: пока
            // владелец ходил в браузере, набор подключений мог измениться.
            if phase == .active { Task { await externalApps.refresh(); await composio.load(force: true) } }
        }
        .task {
            viewModel.loadAppleState()
            await externalApps.refresh()
            await composio.load()
            await viewModel.loadWebhookStatus()
            await viewModel.loadGoogleStatus()
        }
    }

    @ViewBuilder
    private var webhookAccessory: some View {
        HStack(spacing: TFSpacing.sm) {
            Group {
                switch viewModel.webhookStatus {
                case .loading:
                    Text("Проверка…").foregroundStyle(Color.tfSub)
                case .unavailable:
                    Text("статус недоступен").foregroundStyle(Color.tfCoral)
                case .none:
                    Text("нет подписок").foregroundStyle(Color.tfSub)
                case .disabled:
                    Text("выключены").foregroundStyle(Color.tfSub)
                case .failed:
                    Text("есть ошибка").foregroundStyle(Color.tfCoral)
                case .active(let count):
                    Text(count == 1 ? "включён" : "включены: \(count)")
                        .foregroundStyle(Color.tfGreen)
                }
            }
            .tfText(.action)
            .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(Color.tfDim)
        }
        .accessibilityIdentifier("integrations.webhooks.status")
    }

    private var dividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }

    private func integrationGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text(title).tfText(.body).foregroundStyle(Color.tfSub)
            TFCard(padding: 0) { VStack(spacing: 0) { content() } }
        }
    }

    private func successBanner(_ text: String) -> some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: "checkmark").font(.system(size: 16)).foregroundStyle(Color.tfSub)
            Text(text).tfText(.action).foregroundStyle(Color.tfSub)
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard)
        .overlay(RoundedRectangle(cornerRadius: TFRadius.xl).strokeBorder(Color.tfSub.opacity(0.3), lineWidth: TFBorder.width))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
    }

    // MARK: - Apple Экосистема (iOS)

    private var appleSection: some View {
        integrationGroup("Apple Экосистема (iOS)") {
            appleCalendarAccordion
            TFDivider(inset: dividerInset)
            appleRemindersAccordion
        }
    }

    private var appleCalendarAccordion: some View {
        IntegrationAccordionCard(
            icon: "calendar", title: "Apple Календарь",
            subtitle: appleCalendarSubtitle,
            badge: viewModel.calPermGranted ? "В сети" : nil,
            isExpanded: $isAppleCalOpen
        ) {
            if !viewModel.calPermGranted {
                TFButton("Разрешить доступ к Apple Календарю", variant: .primary) {
                    Task { await viewModel.requestCalendarAccess() }
                }
            } else if viewModel.appleCalendars.isEmpty {
                Text("Календари не найдены").tfText(.action).foregroundStyle(Color.tfSub)
            } else {
                Text("Отображать календари в расписании:").tfText(.caption).fontWeight(.medium).foregroundStyle(Color.tfSub)
                VStack(spacing: 0) {
                    ForEach(viewModel.appleCalendars, id: \.calendarIdentifier) { calendar in
                        CalendarCheckRow(
                            color: Color(cgColor: calendar.cgColor),
                            title: calendar.title,
                            isChecked: viewModel.selectedAppleCalendarIds.isEmpty || viewModel.selectedAppleCalendarIds.contains(calendar.calendarIdentifier),
                            action: { viewModel.toggleAppleCalendar(calendar.calendarIdentifier) }
                        )
                    }
                }
                .padding(TFSpacing.xs)
                .background(Color.tfCard2.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            }
        }
    }

    private var appleCalendarSubtitle: String {
        guard viewModel.calPermGranted else { return "Требуется разрешение" }
        guard !viewModel.appleCalendars.isEmpty else { return "Доступ открыт" }
        let count = viewModel.selectedAppleCalendarIds.isEmpty ? "все" : "\(viewModel.selectedAppleCalendarIds.count)"
        return "Выбрано: \(count) из \(viewModel.appleCalendars.count)"
    }

    private var appleRemindersAccordion: some View {
        IntegrationAccordionCard(
            icon: "list.bullet.rectangle.portrait", title: "Apple Напоминания",
            subtitle: viewModel.remPermGranted ? "Двусторонняя синхронизация задач" : "Требуется разрешение",
            badge: viewModel.remPermGranted ? "В сети" : nil,
            isExpanded: $isAppleRemOpen
        ) {
            if !viewModel.remPermGranted {
                TFButton("Разрешить доступ к Apple Напоминаниям", variant: .primary) {
                    Task { await viewModel.requestRemindersAccess() }
                }
            } else {
                if !viewModel.appleReminderLists.isEmpty {
                    listPicker(
                        label: "Список Apple Напоминаний:",
                        options: viewModel.appleReminderLists.map { ($0.calendarIdentifier, $0.title) },
                        selectedId: viewModel.selectedReminderListId ?? "",
                        onSelect: { viewModel.selectReminderList($0) }
                    )
                }
                TFButton(
                    viewModel.isAppleSyncing ? "Синхронизация..." : "Синхронизировать сейчас",
                    icon: "arrow.triangle.2.circlepath", variant: .secondary, isEnabled: !viewModel.isAppleSyncing
                ) {
                    Task { await viewModel.syncAppleReminders(taskStore: taskStore, projectStore: projectStore) }
                }
            }
        }
    }

    // MARK: - Things 3: то же подключение, что в профиле Помощника владельца

    private var thingsSection: some View {
        integrationGroup("MacBook") {
            IntegrationAccordionCard(
                icon: "checkmark.square", asset: "IntegrationThings", title: "Things 3",
                subtitle: externalApps.thingsDetail,
                badge: externalApps.thingsStatus,
                badgeColor: externalApps.thingsReadable ? .tfTeal : .tfSub,
                isExpanded: $isThingsOpen
            ) {
                ExternalAppAccessDetails(app: "things")
                TFButton(externalApps.loading ? "Проверка…" : "Обновить доступность", icon: "arrow.clockwise", variant: .secondary, isEnabled: !externalApps.loading) {
                    Task { await externalApps.refresh() }
                }
            }
        }
    }

    // MARK: - Google Сервисы

    private var googleSection: some View {
        integrationGroup("Google Сервисы") {
            googleTasksAccordion
            TFDivider(inset: dividerInset)
            googleCalendarAccordion
        }
    }

    private var googleTasksAccordion: some View {
        IntegrationAccordionCard(
            icon: "tag", title: "Google Задачи",
            subtitle: googleTasksSubtitle,
            badge: viewModel.googleConnected ? "В сети" : nil,
            isExpanded: $isGoogleTasksOpen
        ) {
            if !viewModel.googleConnected {
                TFButton(viewModel.isGoogleAuthorizing ? "Формирование ссылки..." : "Войти через Google", variant: .primary, isEnabled: !viewModel.isGoogleAuthorizing) {
                    Task { await viewModel.connectGoogle() }
                }
            } else {
                if viewModel.isGoogleListsLoading {
                    Text("Загрузка списков задач...").tfText(.action).foregroundStyle(Color.tfSub)
                } else if !viewModel.googleLists.isEmpty {
                    listPicker(
                        label: "Список Google Tasks:",
                        options: [("@default", "Основной список (@default)")] + viewModel.googleLists.map { ($0.id, $0.title) },
                        selectedId: viewModel.status?.google.settings.listId ?? "@default",
                        onSelect: { id in Task { await viewModel.selectGoogleList(id) } }
                    )
                }
                HStack(spacing: TFSpacing.sm) {
                    TFButton(viewModel.isGoogleSyncing ? "Синхронизация..." : "Синхронизировать", icon: "arrow.triangle.2.circlepath", variant: .secondary, isEnabled: !viewModel.isGoogleSyncing) {
                        Task { await viewModel.syncGoogle() }
                    }
                    disconnectButton
                }
                if let lastSyncedAt = viewModel.status?.google.lastSyncedAt, let date = DateFormats.sqliteUTC(lastSyncedAt) {
                    Text("Последняя синхронизация: \(Self.syncDateFormatter.string(from: date))")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    /// Отключение Google — общая кнопка для обоих аккордеонов (Задачи и
    /// Календарь): учётка в интеграции одна, отключение у сервера тоже одно
    /// (`googleDisconnect`), поэтому и кнопка одна на две секции.
    private var disconnectButton: some View {
        TFButton(
            viewModel.isGoogleDisconnecting ? "Отключение..." : "Отключить",
            icon: "xmark.circle",
            variant: .secondary,
            isEnabled: !viewModel.isGoogleDisconnecting
        ) {
            Task { await viewModel.disconnectGoogle() }
        }
    }

    private var googleTasksSubtitle: String {
        if viewModel.isStatusLoading { return "Проверка..." }
        if viewModel.googleConnected { return viewModel.status?.google.email ?? "Аккаунт подключён" }
        return "Импорт задач и списков"
    }

    private var googleCalendarAccordion: some View {
        IntegrationAccordionCard(
            icon: "calendar", title: "Google Календарь",
            subtitle: googleCalendarSubtitle,
            badge: viewModel.googleConnected ? "В сети" : nil,
            isExpanded: $isGoogleCalOpen
        ) {
            if !viewModel.googleConnected {
                TFButton(viewModel.isGoogleAuthorizing ? "Формирование ссылки..." : "Войти через Google", variant: .primary, isEnabled: !viewModel.isGoogleAuthorizing) {
                    Task { await viewModel.connectGoogle() }
                }
            } else if viewModel.isGoogleCalendarsLoading {
                Text("Загрузка календарей Google...").tfText(.action).foregroundStyle(Color.tfSub)
            } else if !viewModel.googleCalendars.isEmpty {
                Text("Отображать календари Google:").tfText(.caption).fontWeight(.medium).foregroundStyle(Color.tfSub)
                VStack(spacing: 0) {
                    ForEach(viewModel.googleCalendars) { calendar in
                        CalendarCheckRow(
                            color: calendar.backgroundColor.map(Color.init(hex:)) ?? Color(hex: "#4285F4"),
                            title: calendar.primary == true ? "\(calendar.summary) (Основной)" : calendar.summary,
                            isChecked: viewModel.selectedGoogleCalendarIds.isEmpty || viewModel.selectedGoogleCalendarIds.contains(calendar.id),
                            action: { viewModel.toggleGoogleCalendar(calendar.id) }
                        )
                    }
                }
                .padding(TFSpacing.xs)
                .background(Color.tfCard2.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            } else {
                Text("Календари не найдены или нет доступа").tfText(.action).foregroundStyle(Color.tfSub)
            }
        }
    }

    private var googleCalendarSubtitle: String {
        guard viewModel.googleConnected else { return "Требуется вход с Google" }
        guard !viewModel.googleCalendars.isEmpty else { return "События в Предстоящем и Сегодня" }
        let count = viewModel.selectedGoogleCalendarIds.isEmpty ? "все" : "\(viewModel.selectedGoogleCalendarIds.count)"
        return "Выбрано: \(count) из \(viewModel.googleCalendars.count)"
    }

    /// Замена HTML `<select>` — нативный `Menu`, тап показывает системный
    /// список пунктов (ближайший честный эквивалент выпадающего списка на iOS).
    private func listPicker(label: String, options: [(id: String, title: String)], selectedId: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(label).tfText(.caption).foregroundStyle(Color.tfSub)
            Menu {
                ForEach(options, id: \.id) { option in
                    Button(option.title) { onSelect(option.id) }
                }
            } label: {
                HStack {
                    Text(options.first { $0.id == selectedId }?.title ?? selectedId)
                        .tfText(.action).foregroundStyle(Color.tfText).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Color.tfDim)
                }
                .padding(.horizontal, TFSpacing.md)
                .frame(height: TFHitTarget.min)
                .background(Color.tfCard2)
                .overlay(RoundedRectangle(cornerRadius: TFRadius.lg).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            }
        }
    }

    private static let syncDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm:ss"
        return formatter
    }()
}

// MARK: - Аккордеон-карточка (Apple Календарь/Напоминания, Google Задачи/Календарь)

private struct IntegrationAccordionCard<Content: View>: View {
    let icon: String
    var asset: String? = nil
    let title: String
    let subtitle: String
    let badge: String?
    var badgeColor: Color = .tfTeal
    @Binding var isExpanded: Bool
    var identifier: String = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: TFDuration.fast)) { isExpanded.toggle() }
            } label: {
                TFListRow(icon: icon, iconStyle: asset.map { .asset($0) } ?? .plain, title: title, subtitle: subtitle,
                    trailing: AnyView(HStack(spacing: TFSpacing.sm) {
                        if let badge { Text(badge).tfText(.caption).foregroundStyle(badgeColor) }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13)).foregroundStyle(Color.tfDim)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }), titleStyle: .action, verticalPadding: TFSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier.isEmpty ? "integrations.\(icon).\(title)" : identifier)
            .accessibilityValue(isExpanded ? "Развернут" : "Свернут")
            if isExpanded {
                VStack(alignment: .leading, spacing: TFSpacing.sm) { content() }
                    .padding(.horizontal, TFSpacing.lg)
                    .padding(.bottom, TFSpacing.md)
            }
        }
    }
}

/// Строка-чекбокс календаря — цветной кружок + название + галочка при выборе
/// (spec §14, скриншот `settings-integrations.png`).
private struct CalendarCheckRow: View {
    let color: Color
    let title: String
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "calendar").foregroundStyle(color).frame(width: 16)
                Text(title).tfText(.action).foregroundStyle(Color.tfText).lineLimit(1)
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(Color.tfText)
                }
            }
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, TFSpacing.xs + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
    }
}
