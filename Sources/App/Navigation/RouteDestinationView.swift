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
            if reservesTabBarSpace && route != .chat {
                Color.clear.frame(height: TFTabBarMetrics.heightCompact + TFSpacing.sm)
            }
        }
}

@ViewBuilder
private func routeContent(_ route: AppRoute) -> some View {
    switch route {
    case .today:
        TodayScreen()
    case .overview:
        OverviewScreen()
    case .upcoming:
        UpcomingScreen()
    case .timeline:
        TimelineScreen()
    case .chat:
        ChatScreen()
    case .taskDetail(let taskID):
        // Владелец 02.09.2026: открытие любой задачи ведёт сразу в форму
        // редактирования (тот же вид, что раньше был за «…» → «Изменить»),
        // без промежуточного экрана-просмотра — TaskDetailScreen из этого
        // пути убран, её меню «…» (принять/отклонить, Dynamic Island,
        // шаблон) перенесено в TaskFormScreen.
        TaskFormScreen(taskID: taskID)
    case .taskForm(let taskID):
        TaskFormScreen(taskID: taskID)
    case .notes:
        NotesScreen()
    case .noteFolder(let folderID):
        NotesScreen(focusFolderID: folderID)
    case .noteEditor(let noteID):
        NoteEditorScreen(noteID: noteID)
    case .projects:
        ProjectsScreen()
    case .projectTasks(let projectID):
        ProjectTasksScreen(projectID: projectID)
    case .labels:
        LabelsScreen()
    case .labelTasks(let labelID):
        LabelTasksScreen(labelID: labelID)
    case .search:
        SearchScreen()
    case .activity:
        ActivityScreen()
    case .notifications:
        NotificationsScreen()
    case .agents:
        AgentsScreen()
    case .agentWork:
        AgentWorkScreen()
    case .settings:
        SettingsScreen()
    case .integrations:
        IntegrationsScreen()
    case .templates:
        TemplatesScreen()
    case .voiceModels:
        VoiceModelsScreen()
    }
}
