import SwiftUI

/// Единый список задач и почасовой режим внутри «Планирования».
struct TodaySectionView: View {
    @Binding var layout: TodayLayout
    /// Видимая дата почасового режима принадлежит родителю: так заголовок
    /// месяца сразу меняется при перелистывании через границу месяца.
    @Binding var activeHourDate: String
    var onAddTask: () -> Void = {}
    let plannerViewSwitcher: AnyView
    /// Тот же самый `Menu` «Показывать в разделе», что и у диапазонов —
    /// приходит из `UpcomingScreen`, где живёт его состояние (LOCK-111).
    var sectionCompositionMenu: AnyView = AnyView(EmptyView())
    var visibleProjectIds: Set<String> = []
    var showAgentTasks = false
    /// Название текущей вкладки списка — уезжает в системную шапку экрана.
    /// Раньше сюда же уходило название видимой колонки доски.
    var onTitleChange: (String) -> Void = { _ in }

    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(SessionStore.self) private var session

    private let listTab = TodayListTab.today

    @State private var vm = TodayViewModel()
    @State private var sheetTaskID: TodaySectionTaskID?
    @State private var rescheduleOpen = false
    @State private var rescheduleTask: ApiTask?
    @State private var rescheduleTaskIDs: [String]?

    private var today: String { TodayDate.todayString() }

    /// Заголовок секции, до которой долистали. Пока лента в начале — пусто.
    @State private var pinnedSectionTitle = ""
    /// Высота, на которой заголовок секции прилипает к шапке.
    @State private var pinEdge: CGFloat = 0
    /// Что показать в шапке: у списка — заголовок секции, которую сейчас
    /// читают, а пока ни одна не подошла к кромке — название вкладки. У
    /// почасовой сетки шапку рисует родитель по дате.
    /// Владелец 15.09.2026: «я думал, ты заголовки сделаешь динамическими —
    /// пролистываю, они в центр становятся, а они захардкоженные: здесь
    /// „Сегодня“, а у меня тут же предстоящие, это же уже не сегодня».
    private var titleForHeader: String {
        guard layout == .list else { return "" }
        return pinnedSectionTitle.isEmpty ? "Все задачи" : pinnedSectionTitle
    }

    var routineOccurrences: [RoutineOccurrence] = []
    var onOpenRoutine: (RoutineOccurrence) -> Void = { _ in }

    private var currentRoutineOccurrences: [RoutineOccurrence] {
        routineOccurrences.filter { $0.day() == (layout == .hours ? activeHourDate : today) }
    }

    @ViewBuilder private var routineRows: some View {
        ForEach(currentRoutineOccurrences) { occurrence in
            RoutineOccurrenceRow(occurrence: occurrence) { onOpenRoutine(occurrence) }
                .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    private var computation: TodayComputation {
        // Разовые фильтры — свои у экрана, состав раздела — общий с
        // диапазонами и приходит параметрами (LOCK-111).
        var effectiveFilters = vm.filters
        var seen = Set<String>()
        let source = layout == .list ? taskStore.tasks + taskStore.agentWorkTasks : taskStore.tasks
        let tasks = source.filter { seen.insert($0.id).inserted && !$0.isArchived }
        // Множество задач рутин — ОДИН раз на сборку: раньше оно собиралось
        // внутри фильтра, то есть заново на каждую задачу (O(N×M)).
        let routineTaskIDs = Set(routineOccurrences.compactMap(\.taskId))
        return TodayComputation(
            allTasks: layout == .list ? tasks : tasks.filter { !routineTaskIDs.contains($0.id) },
            currentUser: session.currentUser,
            agents: vm.agents,
            filters: effectiveFilters,
            showAgentTasks: showAgentTasks,
            visibleProjectIds: layout == .list ? Set(tasks.compactMap(\.projectId)) : visibleProjectIds,
            today: today,
            activeHourDate: activeHourDate,
            isLoading: taskStore.isLoading,
            isError: taskStore.errorMessage != nil,
            tasksRevision: taskStore.tasksRevision
        )
    }

    var body: some View {
        let c = computation
        Group {
            if layout == .hours {
                hoursContent(c: c)
            } else {
                // Все категории в одной ленте; горизонтальный свайп принадлежит строкам.
                ZStack {
                    // Картинка — пустое состояние вкладки, а не постоянный фон.
                    // Владелец 22.10.2026: «я-то думал, они будут отображаться,
                    // пока нет записи на этой странице… в итоге есть записи —
                    // есть фон, я не этого ожидал». Поэтому картинка живёт
                    // только пока во вкладке нет ни одной задачи. Лежит она ПОД
                    // прокруткой: список едет, картинка стоит. Под ней — цвет
                    // фона приложения, на нём и работает наложение `screen`:
                    // фон остаётся своего цвета, от картинки только светлые
                    // штрихи.
                    Color.tfBackground
                    if isTabEmpty(c) { plannerBackdrop }
                    listContent(c: c)
                    .refreshable { await taskStore.load(silent: true) }
                }
                // Высота, на которой заголовок секции прилипает к шапке.
                // Изнутри прокрутки её не видно (там безопасная зона уже
                // нулевая), поэтому меряем снаружи и отдаём списку.
                .hintAnchor(HintAnchorID.unifiedPlanner)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minY + proxy.safeAreaInsets.top
                } action: { pinEdge = $0 }
            }
        }
        .onAppear { onTitleChange(titleForHeader) }
        .onChange(of: layout) { _, _ in onTitleChange(titleForHeader) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    filterMenu(c: c).tfPlannerWideControl()
                    plannerViewSwitcher.tfPlannerWideControl()
                }
            }
        }
        .task { await vm.loadAgentsIfNeeded() }
        .taskCardSheet(item: $sheetTaskID)
        .tfBottomSheet(isPresented: $rescheduleOpen, title: "Срок") {
            RescheduleSheetContent(
                taskIds: rescheduleTaskIDs ?? rescheduleTask.map { [$0.id] } ?? c.overdueTasks.map(\.id),
                taskStore: taskStore,
                onClose: {
                    rescheduleTask = nil
                    rescheduleTaskIDs = nil
                    rescheduleOpen = false
                }
            )
        }
        .onChange(of: rescheduleOpen) { _, open in
            if !open {
                rescheduleTask = nil
                rescheduleTaskIDs = nil
            }
        }
    }

    /// Пуста ли текущая вкладка списка — по тем же наборам задач, что
    /// показывает `TodayListView` (см. `TodayListSection.sections`).
    /// Пока задач нет, вместо списка стоит картинка-пустое состояние.
    private func isTabEmpty(_ c: TodayComputation) -> Bool {
        let sections = TodayListSection.sections(tab: listTab, waiting: c.waitingTasks,
            overdue: c.overdueTasks, today: c.todayTasks, upcoming: c.upcomingTasks, pool: c.poolTasks,
            todayDate: today, occurrences: routineOccurrences)
        return PlannerBackdropVisibility.isVisible(isLoading: taskStore.isLoading,
            hasError: taskStore.errorMessage != nil,
            visibleTaskCount: sections.reduce(0) { $0 + $1.tasks.count + $1.occurrences.count })
    }

    /// Неподвижная картинка-фон текущей вкладки списка: тянется по размеру
    /// экрана и обрезается по его краям. Из прокрутки её не видно — она под
    /// ней, поэтому список едет, а картинка стоит. Касания и озвучку не
    /// принимает: это подложка.
    @ViewBuilder
    private var plannerBackdrop: some View {
        Image(listTab.backdropAssetName)
            .resizable()
            .scaledToFill()
            .opacity(0.5)
            .blendMode(.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func listContent(c: TodayComputation) -> some View {
        VStack(spacing: 0) {
            if taskStore.isLoading && taskStore.tasks.isEmpty {
                TFLoading(.block)
            }
            TFErrorBanner(taskStore.errorMessage, variant: .inline)
                .padding(.horizontal, TFSpacing.lg)

            TodayListView(
                    tab: listTab,
                    waitingTasks: c.waitingTasks,
                    overdueTasks: c.overdueTasks,
                    todayTasks: c.todayTasks,
                    upcomingTasks: c.upcomingTasks,
                    poolTasks: c.poolTasks,
                    today: today,
                    routineOccurrences: routineOccurrences,
                    onOpenRoutine: onOpenRoutine,
                    onOpen: { sheetTaskID = TodaySectionTaskID(id: $0.id) },
                    onComplete: { task in
                        Task {
                            await taskStore.patch(taskId: task.id, fields: ["status": .string("completed")]) { _ in }
                        }
                    },
                    onDelete: { task in Task { await taskStore.delete(taskId: task.id) } },
                    onPinnedSectionChange: { title in
                        guard title != pinnedSectionTitle else { return }
                        pinnedSectionTitle = title
                        // Считаем от свежего значения, а не от `titleForHeader`:
                        // присвоенный `@State` в этом же проходе ещё старый.
                        onTitleChange(title.isEmpty ? "Все задачи" : title)
                    },
                    pinEdge: pinEdge,
                    swipeOnlyAtEdges: false
                )
        }
    }

    @ViewBuilder
    private func hoursContent(c: TodayComputation) -> some View {
        if c.hourDays.isEmpty {
            TFLoading(.block)
        } else {
            let hourDay = c.hourDays[0]
            routineRows
            UpcomingHoursView(
                days: [UpcomingHourColumn(date: hourDay.date, tasks: hourDay.tasks, isToday: hourDay.isToday)],
                projectColor: { task in
                    guard let id = task.projectId,
                          let project = projectStore.projects.first(where: { $0.id == id }) else { return Color(hex: TFHexDefault.unassigned) }
                    return project.color.map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned)
                },
                onTaskTap: { sheetTaskID = TodaySectionTaskID(id: $0) },
                onSchedule: { id, date, time in
                    Task {
                        let existing = taskStore.tasks.first(where: { $0.id == id })
                        var fields: [String: JSONValue] = ["start_time": .string(time), "due_date": .string(date)]
                        if existing?.durationMin == nil { fields["duration_min"] = .number(15) }
                        await taskStore.patch(taskId: id, fields: fields) { _ in }
                    }
                },
                // Растянули плашку за край — длительность (и начало, если
                // тянули за верх) уходят на сервер сразу, без карточки.
                onResize: { id, startTime, minutes in
                    Task {
                        var fields: [String: JSONValue] = ["duration_min": .number(Double(minutes))]
                        if let startTime { fields["start_time"] = .string(startTime) }
                        await taskStore.patch(taskId: id, fields: fields) { _ in }
                    }
                },
                onPage: { direction in
                    activeHourDate = TodayDate.addDays(activeHourDate, direction)
                },
                showsDayHeader: false
            )
            .refreshable {
                await taskStore.load(silent: true)
                await projectStore.load()
            }
        }
    }

    private func filterMenu(c: TodayComputation) -> some View {
        Menu {
            Menu {
                filterOption("Все проекты", selected: vm.filters.projectId == nil) { vm.filters.projectId = nil }
                if c.projectOptions.isEmpty { Text("Нет задач с проектом") }
                else {
                    ForEach(c.projectOptions) { option in
                        filterOption(option.label, selected: vm.filters.projectId == option.id) { vm.filters.projectId = option.id }
                    }
                }
            } label: { Label("Проект", systemImage: "folder") }

            Menu {
                filterOption("Все метки", selected: vm.filters.labelId == nil) { vm.filters.labelId = nil }
                if c.labelOptions.isEmpty { Text("Нет задач с метками") }
                else {
                    ForEach(c.labelOptions) { option in
                        filterOption(option.label, selected: vm.filters.labelId == option.id) { vm.filters.labelId = option.id }
                    }
                }
            } label: { Label("Метка", systemImage: "tag") }

            Menu {
                filterOption("Все исполнители", selected: vm.filters.assigneeKey == nil) { vm.filters.assigneeKey = nil }
                if c.assigneeOptions.hasUnassigned {
                    filterOption("Без исполнителя", selected: vm.filters.assigneeKey == "__none") { vm.filters.assigneeKey = "__none" }
                }
                if c.assigneeOptions.list.isEmpty && !c.assigneeOptions.hasUnassigned { Text("Нет данных об исполнителях") }
                else {
                    ForEach(c.assigneeOptions.list) { option in
                        filterOption(option.name, selected: vm.filters.assigneeKey == option.id) { vm.filters.assigneeKey = option.id }
                    }
                }
            } label: { Label("Исполнитель", systemImage: "person") }

            Divider()

            // «Выполненные» живут внутри этого подменю вместе с проектами и
            // агентскими — состав раздела общий с диапазонами, отдельного
            // переключателя здесь больше нет.
            if layout != .list { sectionCompositionMenu }

            if vm.filters.isActive {
                Divider()
                Button(role: .destructive) { vm.filters = .empty } label: {
                    Label("Сбросить фильтры", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            TFPlannerToolbarIcon(systemName: "line.3.horizontal.decrease", tint: vm.filters.isActive ? .tfRed : .tfText)
        }
        .accessibilityLabel("Фильтры")
        .accessibilityIdentifier("today.filters")
    }

    private func filterOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    // Режим «Выбрать задачи» с массовым переносом срока и удалением жил
    // ТОЛЬКО на доске (LOCK-129) и ушёл вместе с ней: строка списка галочки
    // выбора не рисует, а переделывать её — значит лезть в свежие правки
    // свайпов (LOCK-157/158). Владельцу об этом сказано отдельно; если
    // массовые действия нужны в списке, это отдельная задача.
}

private struct TodaySectionTaskID: Identifiable {
    let id: String
}

private extension TodayListTab {
    /// Картинка-фон вкладки списка (владелец 22.10.2026): «Входящие» —
    /// «если не сейчас, то когда», «Ждут вас» и «Сегодня» — «сегодня тот
    /// самый день» (две из трёх картинок владельца одинаковые).
    var backdropAssetName: String {
        switch self {
        case .inbox: "PlannerBackdropInbox"
        case .attention: "PlannerBackdropAttention"
        case .today: "PlannerBackdropToday"
        }
    }
}
