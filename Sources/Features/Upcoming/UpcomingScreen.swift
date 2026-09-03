import SwiftUI

// Обёртка для использования String в .sheet(item:) — стандартный String не Identifiable.
private struct IdentifiableDate: Identifiable, Equatable {
    let id: String
}

// Экран «Планирование» (`/upcoming`) — spec/SCREENS-1.md §5.2. Имя структуры
// и параметры инициализации фиксированы контрактом (spec/INTEGRATION.md):
// `UpcomingScreen`, без параметров.
public struct UpcomingScreen: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore

    @State private var agentsProvider = UpcomingAgentsProvider()

    enum ViewMode: String { case list, week, month, hours }

    /// `upcomingLayout` (spec §4.4) — persist между запусками, дефолт «месяц»
    /// (тот же вид, что на эталонном скриншоте `spec/screenshots/upcoming.png`).
    @AppStorage("upcomingLayout") private var upcomingLayoutRaw = ViewMode.month.rawValue
    private var view: ViewMode {
        get { ViewMode(rawValue: upcomingLayoutRaw) ?? .month }
        nonmutating set { upcomingLayoutRaw = newValue.rawValue }
    }

    @State private var filters = UpcomingTaskFilters.empty
    @State private var selectedDate: String?
    @State private var openDay: String?
    @State private var pushedTaskID: String?
    @State private var editingTaskID: String?
    @State private var rescheduleTask: ApiTask?
    @State private var rescheduleOpen = false

    @State private var gridMonday = UpcomingDate.mondayOf(UpcomingDate.todayString())
    /// Опциональный: до первого появления экрана и до прихода первого
    /// `onVisibleMonthChange` — пусто. Без этого View запоминал бы месяц
    /// на момент своей инициализации (запуск в августе → в сентябре всё
    /// ещё показывает август).
    @State private var gridMonth: (year: Int, month: Int)? = nil
    private let monthGridInitialMonday = UpcomingDate.mondayOf(UpcomingDate.todayString())

    /// Зеркало `store/index.ts` `plannerVisibleProjects` — общая точка со
    /// «Сегодня» (спека §4.4: тот же ключ, opt-in список видимых в
    /// ежедневнике проектов). Ключ ЛИТЕРАЛЬНЫЙ — как `taskflow_today_badge_seen_date`
    /// у `RootShellView` — так автор «Сегодня» может завести тот же ключ и
    /// оба экрана честно разделят состояние без общего Core-стора.
    @State private var plannerVisibleProjectIds: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "plannerVisibleProjects") ?? []
    )

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            belowContentView

            if let banner = emptyFilterBanner {
                banner
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tfNativeHeader("Планирование", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Вид", selection: Binding(get: { view }, set: { view = $0 })) {
                        Label("Список", systemImage: "list.bullet").tag(ViewMode.list)
                        Label("Неделя", systemImage: "calendar.day.timeline.leading").tag(ViewMode.week)
                        Label("Месяц", systemImage: "calendar").tag(ViewMode.month)
                        Label("Три дня", systemImage: "clock").tag(ViewMode.hours)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Выбрать представление")
                .accessibilityIdentifier("upcoming.view-switcher")
            }
        }
        .background(Color.tfBackground)
        .sheet(item: Binding(get: { openDay.map(IdentifiableDate.init) }, set: { _ in openDay = nil })) { day in
            daySheet(date: day.id)
        }
        .sheet(item: $rescheduleTask) { task in rescheduleSheet(task: task) }
        .navigationDestination(isPresented: Binding(
            get: { pushedTaskID != nil }, set: { if !$0 { pushedTaskID = nil } }
        )) {
            if let id = pushedTaskID { routeDestination(.taskDetail(taskID: id)) }
        }
        .navigationDestination(isPresented: Binding(
            get: { editingTaskID != nil }, set: { if !$0 { editingTaskID = nil } }
        )) {
            if let id = editingTaskID { routeDestination(.taskForm(taskID: id)) }
        }
        .task { await agentsProvider.load() }
        .onAppear {
            // Сбрасываем заголовок на месяц «сегодня» каждый раз при появлении
            // экрана (а не только при первом создании View — иначе View,
            // созданный в августе, остаётся с августом и в сентябре).
            gridMonth = UpcomingDate.yearMonth(UpcomingDate.todayString())
        }
    }

    @ViewBuilder
    private var content: some View {
        if taskStore.isLoading {
            TFLoading(.block)
        } else if let error = taskStore.errorMessage {
            TFErrorBanner(error, variant: .block).padding(.horizontal, TFSpacing.screenHorizontal)
        } else {
            switch view {
            case .list:
                UpcomingListView(
                    tasks: tasks, selectedDate: $selectedDate,
                    onTaskTap: { pushedTaskID = $0 },
                    onEditTask: { editingTaskID = $0 },
                    onDeleteTask: { deleteTask($0) },
                    onRescheduleTask: { task in rescheduleTask = task; rescheduleOpen = true }
                )
            case .week:
                UpcomingWeekView(
                    monday: gridMonday, byDate: byDate,
                    onTaskTap: { pushedTaskID = $0 },
                    onDayTap: { openDay = $0 },
                    onPickDate: { gridMonday = UpcomingDate.mondayOf($0) },
                    onPrevWeek: { gridMonday = UpcomingDate.addDays(gridMonday, -7) },
                    onNextWeek: { gridMonday = UpcomingDate.addDays(gridMonday, 7) }
                )
            case .month:
                UpcomingMonthView(
                    initialMonday: monthGridInitialMonday,
                    initialMonth: UpcomingDate.yearMonth(UpcomingDate.todayString()),
                    byDate: byDate, openDay: openDay,
                    onDayTap: { d in openDay = openDay == d ? nil : d },
                    onTaskTap: { pushedTaskID = $0 },
                    onVisibleMonthChange: { y, m in gridMonth = (y, m) }
                )
            case .hours:
                UpcomingHoursView(
                    days: hourDays,
                    projectColor: { task in
                        Color(hex: projectStore.projects.first { $0.id == task.projectId }?.color ?? "#717171")
                    },
                    onTaskTap: { pushedTaskID = $0 },
                    onSchedule: { id, date, time in schedule(id: id, date: date, time: time) }
                )
            }
        }
    }

    /// Нативная шторка — тот же приём, что `TodayScreen.sheetTaskID`: свой
    /// `NavigationStack` ради toolbar (крестик слева, «Готово» справа),
    /// системный хендл вместо самодельного (просьба владельца 03.09.2026 —
    /// «пусть Apple сама сделает скругление и открытие-закрытие», от нас
    /// только правильное расположение задач).
    @ViewBuilder
    private func daySheet(date openDay: String) -> some View {
        NavigationStack {
            UpcomingDaySheetContent(
                date: openDay, tasks: byDate[openDay] ?? [],
                onTaskTap: { self.openDay = nil; pushedTaskID = $0 },
                onPrevDay: { self.openDay = UpcomingDate.addDays(openDay, -1) },
                onNextDay: { self.openDay = UpcomingDate.addDays(openDay, 1) }
            )
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .tfNativeHeader(UpcomingDaySheetTitle.text(openDay), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { self.openDay = nil } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { self.openDay = nil }
                }
            }
        }
        .presentationDragIndicator(.visible) // родной хендл шторки, свой больше не рисуем
        .presentationCornerRadius(TFRadius.sheet)
        .presentationBackground(Color.tfCard)
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func rescheduleSheet(task: ApiTask) -> some View {
        RescheduleSheetContent(
            taskIds: [task.id],
            taskStore: taskStore,
            onClose: {
                rescheduleTask = nil
                rescheduleOpen = false
            }
        )
    }

    /// Нативное системное меню — тот же приём, что `TodayScreen.filterMenu`:
    /// стеклянный попап вместо самодельной шторки-карточки (просьба владельца
    /// 03.09.2026 — «Планирование» должно быть нативным, как «Сегодня»).
    /// Полоска чипов «Показывать в разделе» с кнопкой «+» отсюда пропала по
    /// той же причине, что и у «Сегодня» (см. TodayScreen.swift): у `Menu`
    /// нет способа открыть себя программно на нужном пункте, а сам выбор
    /// проектов никуда не делся — он в подменю «Показывать в разделе» ниже.
    private var filterMenu: some View {
        let projectOptions = UpcomingFilterEngine.projectOptions(optionDatedTasks)
        let labelOptions = UpcomingFilterEngine.labelOptions(optionDatedTasks)
        let assigneeOptions = UpcomingFilterEngine.assigneeOptions(optionDatedTasks)
        return Menu {
            Menu {
                filterOption("Все проекты", selected: filters.projectId == nil) { filters.projectId = nil }
                if projectOptions.isEmpty {
                    Text("Нет задач с проектом")
                } else {
                    ForEach(projectOptions) { option in
                        filterOption(option.label, selected: filters.projectId == option.id) { filters.projectId = option.id }
                    }
                }
            } label: {
                Label("Проект", systemImage: "folder")
            }

            Menu {
                filterOption("Все метки", selected: filters.labelId == nil) { filters.labelId = nil }
                if labelOptions.isEmpty {
                    Text("Нет задач с метками")
                } else {
                    ForEach(labelOptions) { option in
                        filterOption(option.label, selected: filters.labelId == option.id) { filters.labelId = option.id }
                    }
                }
            } label: {
                Label("Метка", systemImage: "tag")
            }

            Menu {
                filterOption("Все исполнители", selected: filters.assigneeKey == nil) { filters.assigneeKey = nil }
                if assigneeOptions.hasUnassigned {
                    filterOption("Без исполнителя", selected: filters.assigneeKey == "__none") { filters.assigneeKey = "__none" }
                }
                if assigneeOptions.list.isEmpty && !assigneeOptions.hasUnassigned {
                    Text("Нет данных об исполнителях")
                } else {
                    ForEach(assigneeOptions.list) { option in
                        filterOption(option.name, selected: filters.assigneeKey == option.id) { filters.assigneeKey = option.id }
                    }
                }
            } label: {
                Label("Исполнитель", systemImage: "person")
            }

            Divider()

            Toggle(isOn: Binding(get: { filters.showCompleted }, set: { filters.showCompleted = $0 })) {
                Label("Показывать выполненные", systemImage: "checkmark.circle")
            }

            Menu {
                if projectStore.projects.isEmpty {
                    Text("Нет проектов")
                } else {
                    ForEach(projectStore.projects) { project in
                        filterOption(project.name, selected: plannerVisibleProjectIds.contains(project.id)) {
                            togglePlannerVisibleProject(project.id)
                        }
                    }
                }
            } label: {
                Label("Показывать в разделе", systemImage: "eye")
            }

            if filters.isActive {
                Divider()
                Button(role: .destructive) { filters = .empty } label: {
                    Label("Сбросить фильтры", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(filters.isActive ? Color.tfRed : Color.tfText)
        }
        .accessibilityLabel("Фильтры")
        .accessibilityIdentifier("upcoming.filters")
    }

    private func filterOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var openDaySheetBinding: Binding<Bool> {
        Binding(get: { openDay != nil && view == .week }, set: { if !$0 { openDay = nil } })
    }

    // MARK: - Данные

    private var today: String { UpcomingDate.todayString() }

    /// Агентские задачи сюда не попадают вовсе, и только due_date ≥ сегодня —
    /// «Планирование» никогда не показывает просроченное (спека §5.2).
    private var datedTasks: [ApiTask] {
        taskStore.tasks.filter { t in
            !UpcomingFilterEngine.isAgentAssigned(t, agentsProvider.agents)
                && t.dueDate != nil && t.dueDate! >= today
                && (t.projectId == nil || plannerVisibleProjectIds.contains(t.projectId!))
        }
    }

    /// Тот же «раздел», но БЕЗ сужения по видимым проектам — источник опций
    /// фильтра «Проект» (спека §4.3: опции должны показывать что МОЖНО
    /// добавить, а не что уже добавлено).
    private var optionDatedTasks: [ApiTask] {
        taskStore.tasks.filter { t in
            !UpcomingFilterEngine.isAgentAssigned(t, agentsProvider.agents) && t.dueDate != nil && t.dueDate! >= today
        }
    }

    private var tasks: [ApiTask] { UpcomingFilterEngine.filter(datedTasks, filters) }
    private var byDate: [String: [ApiTask]] { UpcomingDate.groupByDate(tasks) }

    private var hourDays: [UpcomingHourColumn] {
        (0..<3).map { i in
            let date = UpcomingDate.addDays(today, i)
            return UpcomingHourColumn(date: date, tasks: byDate[date] ?? [], isToday: date == today)
        }
    }

    /// Состояния общие для оставшихся 3 видов (Неделя/Месяц/Три дня) — в
    /// «Список» такой баннер владелец 03.09.2026 явно попросил НЕ добавлять
    /// («убираем из списков эту хрень»): там сброс фильтров живёт только
    /// пунктом внутри Menu фильтров, и всё. Здесь — случай, что не покрыт
    /// загрузкой/ошибкой: фильтры вычистили список подчистую.
    private var emptyFilterBanner: AnyView? {
        guard view != .list, selectedDate == nil, !taskStore.isLoading, taskStore.errorMessage == nil,
              !datedTasks.isEmpty, tasks.isEmpty else { return nil }
        return AnyView(
            HStack(spacing: 6) {
                Text("Под выбранные фильтры ничего не подошло").tfText(.action).foregroundStyle(Color.tfDim)
                Button("Сбросить фильтры") { filters = .empty }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.tfRed)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal).padding(.vertical, TFSpacing.sm)
        )
    }

    @ViewBuilder
    private var belowContentView: some View {
        switch view {
        case .week:
            let (year, month) = UpcomingDate.weekMonth(monday: gridMonday)
            Text("\(UpcomingDate.monthsNom[month]) \(year)")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.screenHorizontal).padding(.bottom, 6)
        case .month:
            let m = gridMonth ?? UpcomingDate.yearMonth(UpcomingDate.todayString())
            Text(UpcomingDate.monthsNom[m.month])
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.screenHorizontal).padding(.bottom, 6)
        case .hours:
            UpcomingDayColumnsHeader(days: hourDays)
        case .list:
            EmptyView()
        }
    }

    // MARK: - Действия

    private func deleteTask(_ id: String) {
        Task { await taskStore.delete(taskId: id) }
    }

    private func schedule(id: String, date: String, time: String) {
        let hadDuration = taskStore.tasks.first { $0.id == id }?.durationMin != nil
        var fields: [String: JSONValue] = ["due_date": .string(date), "start_time": .string(time)]
        // duration_min шлётся ТОЛЬКО когда его раньше не было — иначе PATCH
        // затёр бы уже заданную длительность (спека §3.5: 15 минут только
        // «если раньше не было»; отсутствие ключа ≠ .null в JSONValue-контракте PATCH).
        if !hadDuration { fields["duration_min"] = 15 }
        Task {
            // apply-замыкание TaskStore.patch не может частично обновить
            // локальную копию: поля `ApiTask` — `let` (структура собирается
            // только через `Decodable.init`, без memberwise-инициализатора),
            // править их точечно нельзя без правки Core. Оставляю пустым —
            // UI обновится по факту ответа сервера (небольшая задержка вместо
            // истинно оптимистичного отклика), см. отчёт.
            await taskStore.patch(taskId: id, fields: fields) { _ in }
        }
    }

    private func togglePlannerVisibleProject(_ id: String) {
        if plannerVisibleProjectIds.contains(id) {
            plannerVisibleProjectIds.remove(id)
        } else {
            plannerVisibleProjectIds.insert(id)
        }
        UserDefaults.standard.set(Array(plannerVisibleProjectIds), forKey: "plannerVisibleProjects")
    }
}

/// Заголовок `DaySheet` — «20 августа», отдельно от общей `UpcomingDate`,
/// т.к. нужен только шапке шторки (сама шторка использует общий `TFBottomSheetContent`).
enum UpcomingDaySheetTitle {
    static func text(_ date: String) -> String {
        let (_, month) = UpcomingDate.yearMonth(date)
        return "\(UpcomingDate.day(date)) \(UpcomingDate.monthsGen[month])"
    }
}
