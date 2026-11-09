import SwiftUI

/// Фабрика «маршрут → вью» — spec/INTEGRATION.md, правило 1 и 3: сейчас
/// ветки написанных экранов уже отдают настоящие вью, остальные — заглушку
/// `…ScreenStub`; по мере готовности экрана оркестратор меняет его ветку
/// одной строкой, структуру `switch` трогать не нужно.
/// Писатели экранов сюда не ходят (файл в `Sources/App/`, правило 2 контракта).
///
/// Отступ снизу под `TFTabBar` — здесь, а не в каждом экране по отдельности
/// и не в `RootShellView` (там `.safeAreaInset` до запушенных экранов не
/// доходит — см. её комментарий). Единственная общая точка, через которую
/// проходят и корневые вкладки, и все `.navigationDestination`-пуши —
/// просьба владельца 03.09.2026: «невидимая плашка чуть выше панели,
/// естественный стопор», без ручной заплатки на каждом ScrollView-экране.
/// `.chat` — исключение: там вместо панели своя строка ввода снизу.
///
/// `reservesTabBarSpace` — тем же вечером панель научилась прятаться на
/// ЛЮБОМ пуше (`RootShellView.shouldHideTabBar`), а эта невидимая плашка —
/// нет: она вешалась одинаково и на корневые вкладки, и на запушенные
/// экраны, поэтому под скрытой панелью оставался пустой зарезервированный
/// зазор её высоты — на экране с клавиатурой (редактор заметки) он «ехал»
/// вместе с ней, ровно как раньше сама панель. Владелец 03.09.2026:
/// «менюшку убрал, но подложку — нет, она так же само поднимается».
/// Корневые вкладки (`navigationStack(for:)`, там панель видна) передают
/// `true`; все прочие вызовы — это `.navigationDestination`-пуши (вложенные
/// в т.ч. — второй, третий уровень пуша тоже пуш, панель на нём скрыта
/// точно так же), поэтому по умолчанию `false` — самих таких мест по
/// экранам десятки, отдельно помечать каждое не нужно.
@ViewBuilder
func routeDestination(_ route: AppRoute, reservesTabBarSpace: Bool = false) -> some View {
    routeContent(route)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if reservesTabBarSpace {
                Color.clear.frame(height: TFTabBarMetrics.heightCompact + TFSpacing.sm)
            }
        }
}

@ViewBuilder
private func routeContent(_ route: AppRoute) -> some View {
    switch route {
    case .overview:
        OverviewScreen()
    case .upcoming:
        AttentionScreen()
    case .chat:
        // Вкладка «Чат» ведёт в СПИСОК чатов, а не сразу в открытый чат:
        // сначала меню чатов, потом конкретный чат (владелец 21.09.2026).
        // Каждый чат (роли, Помощник, групповые, проектные) выключает
        // настройку шрифтов: владелец 01.11.2026 просил чаты не трогать.
        RoleChatsScreen().tfChatTypography()
    case .taskDetail(let taskID):
        // Пуше внутрь NavigationStack, а не лист: свайп вниз здесь не
        // работает, поэтому карточке нужен явный «×» (LOCK-TICKET-PUSH-EXIT).
        TaskFormScreen(taskID: taskID, isPushedInNavigationStack: true)
    case .taskCreate:
        TaskFormScreen()
    case .notes:
        NotesScreen()
    case .noteCreate:
        NotesScreen(startsNewNote: true)
    case .noteFolder(let folderID):
        NotesScreen(focusFolderID: folderID)
    case .noteEditor(let noteID):
        NoteEditorScreen(noteID: noteID)
    case .projects:
        ProjectsScreen()
    case .projectCreate:
        ProjectsScreen(opensCreateForm: true)
    case .knowledge:
        // С 09.11.2026 «База знаний» — полки датасетов RAGFlow, а дневник
        // заметок открывается оттуда (.notes/.noteCreate/.noteFolder).
        KnowledgeBaseScreen()
    case .projectTasks(let projectID):
        ProjectTasksScreen(projectID: projectID)
    case .taskArchive:
        TaskArchiveScreen()
    case .allTasks:
        ProjectTasksScreen(projectID: nil)
    case .activity:
        AIUsageScreen()
    case .routines:
        RoutinesScreen()
    case .notifications:
        NotificationsScreen()
    case .agents:
        AgentsScreen()
    case .roleRunJobs:
        RoleRunJobsScreen()
    case .memory:
        MemoryScreen()
    case .taskflowMemory:
        TaskflowMemoryScreen()
    case .missionControl(let taskID):
        MissionControlScreen(taskID: taskID)
    case .settings:
        SettingsScreen().tfSuppressRedOutline()
    case .hints:
        HintsScreen().tfSuppressRedOutline()
    case .integrations:
        IntegrationsScreen().tfSuppressRedOutline()
    case .fontSettings:
        FontSettingsScreen().tfSuppressRedOutline()
    case .voiceModels:
        VoiceModelsScreen().tfSuppressRedOutline()
    case .secretaryVoicePicker:
        SecretaryVoicePickerScreen().tfSuppressRedOutline()
    case .jevSettings:
        JevSettingsScreen().tfSuppressRedOutline()
    case .memoryObserverSettings:
        MemoryObserverSettingsScreen().tfSuppressRedOutline()
    case .contextSources:
        ContextSourcesScreen().tfSuppressRedOutline()
    case .runtimeProviders:
        RuntimeProvidersScreen().tfSuppressRedOutline()
    case .providerDetail(let providerID):
        ProviderDetailScreen(providerID: providerID).tfSuppressRedOutline()
    case .serverSettings:
        ServerSettingsScreen().tfSuppressRedOutline()
    case .secrets:
        SecretsScreen().tfSuppressRedOutline()
    case .diagnostics:
        AppDiagnosticsScreen().tfSuppressRedOutline()
    case .roleLoad:
        RoleLoadScreen()
    case .escalationSettings:
        EscalationSettingsScreen().tfSuppressRedOutline()
    case .runtimeStatus:
        RuntimeStatusScreen().tfSuppressRedOutline()
    case .serviceAccounts:
        ServiceAccountsScreen().tfSuppressRedOutline()
    case .remoteMachines:
        RemoteMachinesScreen().tfSuppressRedOutline()
    case .agentProfile(let id):
        AgentProfileScreen(roleID: id)
    case .chatArchive:
        ChatArchiveScreen()
    case .chatSearch:
        ChatSearchScreen()
    case .chatRole(let id):
        RoleChatsScreen(openedScope: .role(id)).tfChatTypography()
    case .chatGroups:
        RoleChatsScreen(openedScope: .groups).tfChatTypography()
    case .roleChat(let id):
        // Комната грузится по идентификатору: маршрут несёт только id, а
        // состав и последнее сообщение берутся запросом (LOCK-195).
        RoleChatRoomLoader(chatID: id).tfChatTypography()
    }
}
