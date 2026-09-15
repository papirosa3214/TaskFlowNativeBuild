import SwiftUI

/// Раздел «Сегодня» внутри «Планирования». Шапку и выбор раздела рисует
/// `UpcomingScreen`; здесь живут только три подви́да и их фильтры.
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
    var showCompleted = false
    /// Название видимой колонки доски — уезжает в системную шапку экрана.
    var onBoardColumnChange: (String) -> Void = { _ in }

    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(SessionStore.self) private var session

    @State private var vm = TodayViewModel()
    @State private var sheetTaskID: TodaySectionTaskID?
    @State private var rescheduleOpen = false
    @State private var rescheduleTask: ApiTask?
    @State private var rescheduleTaskIDs: [String]?
    @State private var isBoardSelectionMode = false
    @State private var selectedBoardTaskIDs: Set<String> = []
    @State private var isBulkDeleteConfirmationPresented = false

    private var today: String { TodayDate.todayString() }

    private var computation: TodayComputation {
        // Разовые фильтры — свои у экрана, состав раздела — общий с
        // диапазонами и приходит параметрами (LOCK-111).
        var effectiveFilters = vm.filters
        effectiveFilters.showCompleted = showCompleted
        return TodayComputation(
            allTasks: taskStore.tasks,
            currentUser: session.currentUser,
            agents: vm.agents,
            filters: effectiveFilters,
            showAgentTasks: showAgentTasks,
            visibleProjectIds: visibleProjectIds,
            today: today,
            activeHourDate: activeHourDate,
            isLoading: taskStore.isLoading,
            isError: taskStore.errorMessage != nil
        )
    }

    var body: some View {
        let c = computation
        Group {
            if layout == .hours {
                hoursContent(c: c)
            } else if layout == .board {
                // Канбан сам владеет вертикальной прокруткой каждой
                // колонки. Общая ScrollView связывала все три позиции.
                listOrBoardContent(c: c)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // Общий отступ под панель вкладок (`routeDestination`)
                    // держит доску НАД панелью, а карточки должны уезжать
                    // под неё — как на остальных экранах. Гасим его только
                    // здесь; сам общий механизм не трогаем, запас под
                    // последнюю карточку добавлен внутри колонок.
                    .ignoresSafeArea(.container, edges: .bottom)
            } else {
                ScrollView {
                    listOrBoardContent(c: c)
                }
                .refreshable { await taskStore.load(silent: true) }
            }
        }
        .toolbar {
            if layout == .board && isBoardSelectionMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        rescheduleTaskIDs = Array(selectedBoardTaskIDs)
                        rescheduleOpen = true
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                    }
                    .disabled(selectedBoardTaskIDs.isEmpty)
                    .accessibilityLabel("Назначить срок выбранным задачам")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isBulkDeleteConfirmationPresented = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedBoardTaskIDs.isEmpty)
                    .accessibilityLabel("Удалить выбранные задачи")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        isBoardSelectionMode = false
                        selectedBoardTaskIDs.removeAll()
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        filterMenu(c: c).tfPlannerWideControl()
                        plannerViewSwitcher.tfPlannerWideControl()
                    }
                }
            }
        }
        .task { await vm.loadAgentsIfNeeded() }
        .sheet(item: $sheetTaskID) { wrapped in
            NavigationStack { TaskFormScreen(taskID: wrapped.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
        .onChange(of: layout) { _, newLayout in
            if newLayout != .board {
                isBoardSelectionMode = false
                selectedBoardTaskIDs.removeAll()
            }
        }
        .confirmationDialog(
            "Удалить выбранные задачи?",
            isPresented: $isBulkDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task { await deleteSelectedBoardTasks() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет удалено задач: \(selectedBoardTaskIDs.count). Восстановить их нельзя.")
        }
    }

    @ViewBuilder
    private func listOrBoardContent(c: TodayComputation) -> some View {
        VStack(spacing: 0) {
            if c.trueEmpty && layout == .list {
                TodayEmptyIllustration()
            } else {
                if taskStore.isLoading && taskStore.tasks.isEmpty {
                    TFLoading(.block)
                }
                TFErrorBanner(taskStore.errorMessage, variant: .inline)
                    .padding(.horizontal, TFSpacing.lg)

                switch layout {
                case .list:
                    TodayListView(
                        todayTasks: c.todayTasks,
                        today: today,
                        onOpen: { sheetTaskID = TodaySectionTaskID(id: $0.id) },
                        onComplete: { task in
                            Task {
                                await taskStore.patch(taskId: task.id, fields: ["status": .string("completed")]) { _ in }
                            }
                        },
                        onDelete: { task in Task { await taskStore.delete(taskId: task.id) } }
                    )
                case .board:
                    TodayBoardView(
                        columns: c.boardColumns,
                        onOpenTask: { sheetTaskID = TodaySectionTaskID(id: $0) },
                        onReschedule: { rescheduleOpen = true },
                        onAddTask: onAddTask,
                        isSelectingTasks: isBoardSelectionMode,
                        selectedTaskIDs: selectedBoardTaskIDs,
                        onToggleTaskSelection: toggleBoardTaskSelection,
                        onToggleColumnSelection: toggleBoardColumnSelection,
                        onVisibleColumnChange: onBoardColumnChange
                    )
                case .hours:
                    EmptyView()
                }
            }
        }
        // Доске нижний отступ не нужен: её колонки прокручиваются под панель
        // вкладок и держат свой запас внутри (см. `TodayBoardView`).
        .padding(.bottom, layout == .board ? 0 : TFSpacing.lg)
    }

    @ViewBuilder
    private func hoursContent(c: TodayComputation) -> some View {
        if c.hourDays.isEmpty {
            TFLoading(.block)
        } else {
            let hourDay = c.hourDays[0]
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
                onPage: { direction in
                    activeHourDate = TodayDate.addDays(activeHourDate, direction)
                },
                showsDayHeader: false
            )
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

            if layout == .board {
                Button {
                    isBoardSelectionMode = true
                    selectedBoardTaskIDs.removeAll()
                } label: {
                    Label("Выбрать задачи", systemImage: "checkmark.circle")
                }
                Divider()
            }

            // «Выполненные» живут внутри этого подменю вместе с проектами и
            // агентскими — состав раздела общий с диапазонами, отдельного
            // переключателя здесь больше нет.
            sectionCompositionMenu

            if vm.filters.isActive {
                Divider()
                Button(role: .destructive) { vm.filters = .empty } label: {
                    Label("Сбросить фильтры", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            TFPlannerToolbarIcon(systemName: "line.3.horizontal.decrease", tint: vm.filters.isActive ? .tfRed : .tfSub)
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

    private func toggleBoardTaskSelection(_ taskID: String) {
        if selectedBoardTaskIDs.contains(taskID) {
            selectedBoardTaskIDs.remove(taskID)
        } else {
            selectedBoardTaskIDs.insert(taskID)
        }
    }

    private func toggleBoardColumnSelection(_ column: TodayBoardColumn) {
        let ids = Set(column.tasks.map(\.id))
        guard !ids.isEmpty else { return }
        if ids.isSubset(of: selectedBoardTaskIDs) {
            selectedBoardTaskIDs.subtract(ids)
        } else {
            selectedBoardTaskIDs.formUnion(ids)
        }
    }

    private func deleteSelectedBoardTasks() async {
        let selectedIDs = selectedBoardTaskIDs
        for taskID in selectedIDs {
            if await taskStore.delete(taskId: taskID) {
                selectedBoardTaskIDs.remove(taskID)
            }
        }
        if selectedBoardTaskIDs.isEmpty {
            isBoardSelectionMode = false
        }
    }
}

private struct TodaySectionTaskID: Identifiable {
    let id: String
}
