import SwiftUI

/// Корневая оболочка после входа: 3 вкладки (Обзор/Планирование/Чат).
/// + центральная кнопка создания, поверх — свой `NavigationStack` (своя
/// история) на каждую вкладку — spec/SCREENS-1.md §1.1, §2.1.
/// `/inbox` не входит в состав — маршрут убран из веба (INTEGRATION.md).
///
/// Панель и меню создания — готовые компоненты `DesignSystem`
/// (`TFTabBar`/`TFCreateMenu`, `Sources/DesignSystem/Navigation/TFTabBar.swift`,
/// появились 31.08.2026 уже по ходу этой задачи) — здесь только их подключение:
/// состояние вкладки/меню, переходы, бейдж «Сегодня». Само оформление панели
/// этот файл не трогает (правило `ARCHITECTURE.md`: DesignSystem — только читать).
/// Черновик быстрой задачи: `.sheet(item:)` требует `Identifiable`, а
/// `TaskFormViewModel` — общий класс формы и своего `id` не имеет.
private struct QuickAddDraft: Identifiable {
    let id = UUID()
    let viewModel: TaskFormViewModel
}

struct RootShellView: View {
    enum Tab: Int, CaseIterable, Hashable {
        /// «Проекты» вынесены отдельной вкладкой 08.09.2026 (владелец: «помимо
        /// обзора сделать ещё отдельную кнопочку проекты»). Раньше туда вёл
        /// только ряд внутри «Обзора». Порядок пунктов — 2 слева, 2 справа от
        /// круглой кнопки создания, `TFTabBar` делит их пополам сам.
        case overview, projects, upcoming, chat

        var route: AppRoute {
            switch self {
            case .overview: .overview
            case .projects: .projects
            case .upcoming: .upcoming
            case .chat: .chat
            }
        }

        var label: String {
            switch self {
            case .overview: "Обзор"
            case .projects: "Проекты"
            case .upcoming: "План"
            case .chat: "Чат"
            }
        }

        /// Имена локальных SVG-ассетов. Все нарисованы на одном 24×24 поле со
        /// stroke 1.75, поэтому их видимый размер не пляшет между вкладками.
        /// У «Сегодня» число накладывает `TFTodayDateIcon`.
        var icon: String {
            switch self {
            case .overview: "TabIconHome"
            case .projects: "TabIconProjects"
            case .upcoming: "TabIconPlanning"
            case .chat: "TabIconChat"
            }
        }
    }

    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @State private var voiceSession = SecretaryVoiceViewModel()
    /// Итог «Возобновить зависшие шаги» из меню «+» (только владелец).
    @State private var resumeStuckMessage: String?

    // spec/SCREENS-1.md §1.1: стартовый экран — «Обзор» (было «Сегодня» —
    // расходилось со спекой и заодно ломало бейдж «Сегодня» ниже: initial-
    // срабатывание onChange помечало бы его просмотренным при каждом запуске).
    @State private var selectedTab: Tab = .overview
    @State private var isCreateMenuOpen = false
    /// Панель быстрого создания задачи: своя вью-модель живёт здесь, чтобы
    /// пережить переход «развернуть» в полную форму без потери введённого.
    ///
    /// Подаётся `.sheet(item:)`, а НЕ `.sheet(isPresented:)` с `if let` внутри:
    /// при втором варианте содержимое замыкания строится в той же транзакции,
    /// где вью-модель ещё `nil`, и шторка открывается пустой во весь экран
    /// (детент из пустого содержимого тоже не применяется). Проверено кадром
    /// симулятора 31.08.2026 — даже отладочный `Text` внутри `if let` не рисовался.
    @State private var quickAddDraft: QuickAddDraft?
    /// «Развернуть» из панели — полная форма с ТОЙ ЖЕ вью-моделью. Через
    /// `fullScreenCover`, а не пуш маршрута `/task/new`: маршрут строит экран
    /// заново и заводит СВОЮ вью-модель, то есть введённое в панели название,
    /// срок и выбранные файлы пропадали бы (проверено по коду `TaskFormScreen`
    /// 01.09.2026 — у него для этого есть `init(expandingFrom:)`).
    @State private var expandedDraft: QuickAddDraft?
    /// Куда переходим ПОСЛЕ закрытия панели: открыть полную форму в той же
    /// транзакции, где закрывается шторка, iOS не даёт — второе окно просто
    /// не появляется. Поэтому «развернуть» лишь запоминает вью-модель, а
    /// показ идёт из `onDismiss` (тем же приёмом сделан переход внутри
    /// `TaskFormScreen`).
    @State private var pendingExpand: TaskFormViewModel?
    @State private var paths: [Tab: NavigationPath] = [:]
    /// Зеркало `taskflow_today_badge_seen_date` из веба (spec §2.1) —
    /// `UserDefaults` вместо `localStorage`, тот же принцип: бейдж гаснет
    /// после первого захода на «Сегодня» в текущий календарный день и не
    /// появляется заново до полуночи, даже если список задач изменился.
    @AppStorage("taskflow_today_badge_seen_date") private var todayBadgeSeenDate: String = ""
    /// Нижняя панель «пилюлей» (LOCK-TABBAR-PILL-20261018) или нынешний таббар.
    /// Тумблер «Таббар-пилюля» в настройках; по умолчанию пилюля — этого просил
    /// владелец 18.10.2026. Ключ общий с `SettingsViewModel`.
    @AppStorage(SettingsViewModel.pillTabBarKey) private var isPillTabBarEnabled = true
    #if DEBUG
    /// Debug-роут `tasksheet:<id>` открывает ту же единую карточку, что и приложение.
    @State private var debugTaskSheetID: String?
    #endif

    @ViewBuilder
    private var mainTabContent: some View {
        if isPillTabBarEnabled {
            TFPillTabBar(items: tabItems, selectedIndex: selectedIndexBinding,
                         isCreateMenuOpen: isCreateMenuOpen,
                         isTabBarVisible: quickAddDraft == nil && (paths[selectedTab]?.isEmpty ?? true),
                         onSelect: handleTabSelection,
                         onCreateTap: { openQuickAddTask() }) { index in
                if let tab = Tab(rawValue: index) { navigationStack(for: tab) }
            }
        } else {
            switch selectedTab {
            case .overview: navigationStack(for: .overview)
            case .projects: navigationStack(for: .projects)
            case .upcoming: navigationStack(for: .upcoming)
            case .chat: navigationStack(for: .chat)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                #if DEBUG
                if let html = ProcessInfo.processInfo.environment["TASKFLOW_PANEL_PREVIEW"] {
                    NavigationStack {
                        ScrollView { RoleReplyMarkdown(text: "```html\n" + html + "\n```", allowsCommands: ProcessInfo.processInfo.environment["TASKFLOW_PANEL_DENIED"] != "1").padding() }
                            .navigationTitle("Панель роли")
                    }
                } else if let command = ProcessInfo.processInfo.environment["TASKFLOW_OWNER_COMMAND_PREVIEW"] {
                    NavigationStack {
                        List {
                            RoleReplyMarkdown(text: "```bash\n" + command + "\n```", allowsCommands: true)
                        }
                        .navigationTitle("Команда роли")
                    }
                } else {
                    mainTabContent
                }
                #else
                mainTabContent
                #endif
            }
            #if DEBUG
            // Отдельный узел (не тот, что несёт `.sheet(item: $quickAddDraft)`
            // ниже) — два `.sheet` на одном модификаторе в SwiftUI ненадёжны.
            // Копия шторки задачи из `TodaySectionView.swift` (detents/индикатор/
            // радиус/фон) — единственный debug-роут, который реально
            // воспроизводит нативную шторку, а не пуш.
            .sheet(isPresented: Binding(
                get: { debugTaskSheetID != nil },
                set: { if !$0 { debugTaskSheetID = nil } }
            )) {
                if let id = debugTaskSheetID {
                    NavigationStack {
                        TaskFormScreen(taskID: id)
                    }
                    .taskCardSheetPresentation()
                }
            }
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Отступ под TFTabBar — теперь в самой `routeDestination` (см.
            // RouteDestinationView.swift): `.safeAreaInset`, повешенный
            // ЗДЕСЬ, снаружи `NavigationStack`, до запушенных экранов не
            // доходил вообще (`.navigationDestination` строит их отдельным
            // вызовом `routeDestination`, вне зоны действия этого модификатора
            // — проверено кадром симулятора 03.09.2026, баг было видно
            // «живьём»). Инсет только на корневых вкладках без единого пуша
            // был бы бесполезен: почти весь список экранов в приложении —
            // как раз запушенные.


        }
        .environment(voiceSession)
        .overlay(alignment: .bottomTrailing) {
            if voiceSession.presentation.isActive && !voiceSession.presentation.isExpanded {
                SecretaryVoiceFloatingControl(viewModel: voiceSession, onOpenChat: openVoiceChat)
                    .padding(.trailing, TFSpacing.lg)
                    .padding(.bottom, 100)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { voiceSession.presentation.isExpanded },
            set: { if !$0 { voiceSession.minimize() } }
        )) {
            SecretaryVoiceScreen(viewModel: voiceSession, onOpenChat: openVoiceChat)
        }
        .onChange(of: session.currentUser?.id) { _, _ in
            Task { await voiceSession.stop() }
        }
        .environment(\.chatBackAction, {
            isCreateMenuOpen = false
            paths[.chat] = NavigationPath()
            selectedTab = .overview
        })
        .environment(\.openRoute, { route in
            paths[selectedTab, default: NavigationPath()].append(route)
        })
        .animation(.easeOut(duration: TFAnimation.createMenu), value: isCreateMenuOpen)
        // Владелец 07.09.2026: панель быстрого создания — надстройка над
        // клавиатурой с замутнённым фоном, а не выезжающая шторка. Отсюда
        // прозрачный `fullScreenCover` вместо `.sheet`: `.sheet` с фокусом в
        // поле резервирует место под клавиатуру и раздувается почти на весь
        // экран, а свой оверлей (фон + карточка у нижней кромки) живёт внутри
        // `QuickAddTaskView`.
        .fullScreenCover(item: $quickAddDraft, onDismiss: {
            if let viewModel = pendingExpand {
                pendingExpand = nil
                expandedDraft = QuickAddDraft(viewModel: viewModel)
            }
        }) { draft in
            QuickAddTaskView(
                viewModel: draft.viewModel,
                onSaved: { quickAddDraft = nil },
                onExpand: {
                    // Развернуть — тот же незаконченный черновик, только
                    // полной формой: вью-модель передаётся как есть,
                    // введённое не теряется.
                    pendingExpand = draft.viewModel
                    quickAddDraft = nil
                }
            )
            .presentationBackground(.clear)
        }
        .alert("Зависшие шаги", isPresented: Binding(
            get: { resumeStuckMessage != nil },
            set: { if !$0 { resumeStuckMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { resumeStuckMessage = nil }
        } message: {
            Text(resumeStuckMessage ?? "")
        }
        .sheet(item: $expandedDraft) { draft in
            NavigationStack {
                TaskFormScreen(expandingFrom: draft.viewModel)
            }
            .taskCardSheetPresentation()
        }
        #if DEBUG
        // Отладочный автопереход: снять экран в симуляторе иначе нечем —
        // тапать по нему из командной строки нельзя, а показывать владельцу
        // нужно конкретный экран, а не только стартовый. Задаётся переменной
        // окружения при запуске, в релиз не попадает.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["TASKFLOW_DEBUG_ROUTE"],
                  raw.isEmpty == false else { return }
            // Небольшая пауза: сторы должны успеть загрузиться, иначе экран
            // откроется пустым и кадр окажется бесполезным.
            try? await Task.sleep(for: .seconds(2))
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "create":
                isCreateMenuOpen = true
            case "quickadd":
                quickAddDraft = QuickAddDraft(viewModel: TaskFormViewModel(taskID: nil))
            case "expand":
                expandedDraft = QuickAddDraft(viewModel: TaskFormViewModel(taskID: nil))
            case "task" where parts.count == 2:
                debugTaskSheetID = parts[1]
            case "tasksheet" where parts.count == 2:
                debugTaskSheetID = parts[1]
            case "notifications": paths[selectedTab, default: NavigationPath()].append(AppRoute.notifications)
            case "projects": paths[selectedTab, default: NavigationPath()].append(AppRoute.projects)
            case "alltasks": paths[selectedTab, default: NavigationPath()].append(AppRoute.allTasks)
            case "settings": paths[selectedTab, default: NavigationPath()].append(AppRoute.settings)
            // 16.10.2026, LOCK-UI-DRIFT-GATE: строка «Параметры» в настройках
            // показывается только владельцу, а обход экранов (UIStyleGateUITests)
            // должен снимать её независимо от того, под кем симулятор вошёл.
            // Роут открывает маршрут напрямую — DEBUG, в релиз не попадает.
            case "serversettings": paths[selectedTab, default: NavigationPath()].append(AppRoute.serverSettings)
            // Экран диагностики — тоже маршрут: без него снять кадр этого
            // экрана на устройстве нечем (тапы по нему руками).
            case "diagnostics": paths[selectedTab, default: NavigationPath()].append(AppRoute.diagnostics)
            // Экран «Загрузка ролей» — тоже маршрут: снять его кадр в
            // симуляторе иначе нечем (тапы руками из командной строки не идут).
            case "roleload": paths[selectedTab, default: NavigationPath()].append(AppRoute.roleLoad)
            case "notes": paths[selectedTab, default: NavigationPath()].append(AppRoute.notes)
            case "noteeditor" where parts.count == 2:
                paths[selectedTab, default: NavigationPath()].append(AppRoute.noteEditor(noteID: parts[1]))
            case "today": selectedTab = .upcoming
            case "upcoming": selectedTab = .upcoming
            case "chat": selectedTab = .chat
            case "rolechat" where parts.count == 2:
                selectedTab = .chat
                paths[.chat, default: NavigationPath()].append(AppRoute.roleChat(id: parts[1]))
            case "agents": paths[selectedTab, default: NavigationPath()].append(AppRoute.agents)
            case "models": paths[selectedTab, default: NavigationPath()].append(AppRoute.runtimeProviders)
            default: break
            }
        }
        #endif
    }

    private var tabItems: [TFTabItem] {
        Tab.allCases.map { tab in
            TFTabItem(icon: tab.icon, accessibilityLabel: tab.label, badgeCount: tab == .upcoming ? todayBadgeCount : nil, showsTodayDate: tab == .upcoming)
        }
    }

    private func openVoiceChat() {
        guard let chatID = voiceSession.presentation.chatID else { return }
        voiceSession.minimize()
        selectedTab = .chat
        paths[.chat] = NavigationPath()
        paths[.chat, default: NavigationPath()].append(AppRoute.roleChat(id: chatID))
    }

    private var selectedIndexBinding: Binding<Int?> {
        Binding(
            get: { selectedTab.rawValue },
            set: { newValue in
                if let newValue, let tab = Tab(rawValue: newValue) {
                    selectedTab = tab
                }
            }
        )
    }

    /// Меню создания прежней панели (`TFTabBar`, тумблер «Таббар-пилюля»
    /// выключен): «+» пилюли меню больше не показывает и сразу открывает
    /// короткое окно создания задачи (владелец 18.10.2026).
    /// Каждый пункт открывает форму сразу, а не соответствующий раздел.
    private var createMenuItems: [TFCreateMenuItem] {
        var items: [TFCreateMenuItem] = [
            TFCreateMenuItem(icon: "checkmark", title: "Задача") {
                // Задача заводится компактной панелью над клавиатурой, а не
                // полноэкранным бланком: владелец так и просил — нажал «плюс»,
                // написал название, сохранил. Полная форма остаётся за кнопкой
                // «развернуть» внутри самой панели.
                openQuickAddTask()
            },
            TFCreateMenuItem(icon: "book", title: "Заметка") {
                openCreateMenuTarget(.noteCreate)
            },
            TFCreateMenuItem(icon: "tray", title: "Проект") {
                openCreateMenuTarget(.projectCreate)
            },
        ]
        // Только владельцу: остальным сервер всё равно ответил бы 403.
        if session.currentUser?.role == .owner {
            items.append(TFCreateMenuItem(icon: "arrow.clockwise", title: "Возобновить шаги") {
                isCreateMenuOpen = false
                Task { await resumeStuckSteps() }
            })
        }
        return items
    }

    /// «+» открывает короткое окно создания задачи сразу, без меню создания
    /// (владелец 18.10.2026: «убрать уже вот эту панельку… а исключительно одно
    /// действие сразу же открывается короткое окно создания задачи»).
    private func openQuickAddTask() {
        isCreateMenuOpen = false
        quickAddDraft = QuickAddDraft(viewModel: TaskFormViewModel(taskID: nil))
    }

    private func resumeStuckSteps() async {
        do {
            let result = try await APIClient().resumeStuckSteps()
            resumeStuckMessage = result.found == 0
                ? "Зависших шагов нет."
                : "Возобновлено: \(result.resumed) из \(result.found)."
        } catch {
            resumeStuckMessage = "Не удалось: нет связи с сервером или нет прав."
        }
    }

    /// Активные задачи со сроком «сегодня» — то же условие, что у веба
    /// (`due_date === todayStr() && status === "active"`, spec §2.1).
    private var todayBadgeCount: Int {
        guard todayBadgeSeenDate != DateFormats.todayString() else { return 0 }
        return taskStore.tasks.count { $0.status == .active && $0.isDueToday }
    }

    /// Root-owned controls participate in UIKit's interactive navigation transition.
    /// Pushed destinations cover them instead of recreating them after the pop.
    @ViewBuilder
    private var rootTabControls: some View {
        // 16.10.2026, владелец (кадр с телефона): на панели быстрого создания
        // нижняя навигация оставалась под формой, поднималась вместе с
        // клавиатурой и просвечивала сквозь прозрачный фон. Причина — не в
        // самой панели: `fullScreenCover` тут прозрачный (LOCK-140, этого
        // требует оформление), и всё, что лежит ПОД ним, остаётся видимым и
        // продолжает жить по safe area окна, которое клавиатура сжимает.
        // Поэтому на время панели таббар и меню «+» просто не рисуются —
        // под формой остаётся только содержимое экрана.
        if quickAddDraft != nil {
            EmptyView()
        } else if isPillTabBarEnabled {
            // В «пилюле» «+» открывает короткое окно создания задачи сразу:
            // меню создания владелец убрал 18.10.2026 — «исключительно одно
            // действие сразу же открывается короткое окно создания задачи».
            EmptyView()
        } else {
            tabControlsContent
        }
    }

    private var tabControlsContent: some View {
        ZStack(alignment: .bottom) {
            if isCreateMenuOpen {
                // Подложка ловит тап мимо и закрывает меню БЕЗ затемнения
                // фона (spec §2.1) — почти нулевая непрозрачность вместо
                // clear, иначе `onTapGesture` не ловит касания.
                Color.black.opacity(0.0001)
                    .ignoresSafeArea()
                    .onTapGesture { isCreateMenuOpen = false }
            }

                VStack(spacing: 0) {
                    if isCreateMenuOpen {
                        TFCreateMenu(items: createMenuItems)
                            .padding(.bottom, TFCreateMenuMetrics.gapAboveTabBar)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                    }
                    TFTabBar(
                        items: tabItems,
                        selectedIndex: selectedIndexBinding,
                        isCreateMenuOpen: isCreateMenuOpen,
                        onSelect: handleTabSelection,
                        onCreateTap: { isCreateMenuOpen.toggle() }
                    )
                }
        }
    }

    /// Выбор вкладки — общий для обоих видов нижней панели (пилюля и таббар).
    private func handleTabSelection(_ index: Int) {
        guard let tab = Tab(rawValue: index) else { return }
        isCreateMenuOpen = false
        // Повторный тап по УЖЕ активной вкладке возвращает в её корень — как в
        // родных приложениях. Без этого из «Проектов» нельзя было вернуться в
        // «Обзор» тапом по самой вкладке: она уже выбрана, ничего не менялось.
        if tab == selectedTab {
            paths[tab] = NavigationPath()
        } else {
            selectedTab = tab
        }
    }

    private func navigationStack(for tab: Tab) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            GeometryReader { viewport in
                routeDestination(tab.route, reservesTabBarSpace: !isPillTabBarEnabled)
                    .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
                    .overlay(alignment: .bottom) { rootTabControls }
            }
            .navigationDestination(for: AppRoute.self) { routeDestination($0, reservesTabBarSpace: false) }
        }
        .toolbar(isPillTabBarEnabled && (quickAddDraft != nil || !(paths[tab]?.isEmpty ?? true)) ? .hidden : .automatic, for: .tabBar)
    }

    private func pathBinding(for tab: Tab) -> Binding<NavigationPath> {
        Binding(
            get: { paths[tab] ?? NavigationPath() },
            set: { paths[tab] = $0 }
        )
    }

    private func openCreateMenuTarget(_ route: AppRoute) {
        isCreateMenuOpen = false
        paths[selectedTab, default: NavigationPath()].append(route)
    }
}
