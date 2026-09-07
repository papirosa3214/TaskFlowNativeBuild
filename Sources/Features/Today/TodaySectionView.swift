import SwiftUI

/// Раздел «Сегодня» внутри «Планирования». Шапку и выбор раздела рисует
/// `UpcomingScreen`; здесь живут только три подви́да и их фильтры.
struct TodaySectionView: View {
    @Binding var layout: TodayLayout
    var onAddTask: () -> Void = {}
    let plannerViewSwitcher: AnyView

    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(SessionStore.self) private var session

    @State private var vm = TodayViewModel()
    @State private var sheetTaskID: TodaySectionTaskID?
    @State private var rescheduleOpen = false
    @State private var rescheduleTask: ApiTask?

    private var today: String { TodayDate.todayString() }
    private var activeHourDate: String {
        vm.hourDateOffset == 0 ? today : TodayDate.addDays(today, vm.hourDateOffset)
    }

    private var computation: TodayComputation {
        TodayComputation(
            allTasks: taskStore.tasks,
            currentUser: session.currentUser,
            agents: vm.agents,
            filters: vm.filters,
            visibleProjectIds: vm.visibleProjectIds,
            hasConfiguredVisibleProjects: vm.hasConfiguredVisibleProjects,
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
                listOrBoardContent(c: c)
            } else {
                ScrollView {
                    listOrBoardContent(c: c)
                }
                .refreshable { await taskStore.load(silent: true) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    filterMenu(c: c).tfPlannerToolbarControl()
                    plannerViewSwitcher.tfPlannerToolbarControl()
                }
            }
        }
        .task { await vm.loadAgentsIfNeeded() }
        .sheet(item: $sheetTaskID) { wrapped in
            NavigationStack { TaskFormScreen(taskID: wrapped.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .tfBottomSheet(isPresented: $rescheduleOpen) {
            RescheduleSheetContent(
                taskIds: rescheduleTask.map { [$0.id] } ?? c.overdueTasks.map(\.id),
                taskStore: taskStore,
                onClose: {
                    rescheduleTask = nil
                    rescheduleOpen = false
                }
            )
        }
        .onChange(of: rescheduleOpen) { _, open in
            if !open { rescheduleTask = nil }
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
                        waitingTasks: c.waitingTasks,
                        overdueTasks: c.overdueTasks,
                        todayTasks: c.todayTasks,
                        today: today,
                        onOpen: { sheetTaskID = TodaySectionTaskID(id: $0.id) },
                        onComplete: { task in
                            Task {
                                await taskStore.patch(taskId: task.id, fields: ["status": .string("completed")]) { _ in }
                            }
                        },
                        onReschedule: { task in
                            rescheduleTask = task
                            rescheduleOpen = true
                        },
                        onDelete: { task in Task { await taskStore.delete(taskId: task.id) } }
                    )
                case .board:
                    TodayBoardView(
                        columns: c.boardColumns,
                        onOpenTask: { sheetTaskID = TodaySectionTaskID(id: $0) },
                        onReschedule: { rescheduleOpen = true },
                        onAddTask: onAddTask
                    )
                    .padding(.top, TFSpacing.sm)
                case .hours:
                    EmptyView()
                }
            }
        }
        .padding(.bottom, TFSpacing.lg)
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
                          let project = projectStore.projects.first(where: { $0.id == id }) else { return .tfDim }
                    return project.color.map { Color(hex: $0) } ?? .tfDim
                },
                onTaskTap: { sheetTaskID = TodaySectionTaskID(id: $0) },
                onSchedule: { id, date, time in
                    Task {
                        let existing = taskStore.tasks.first(where: { $0.id == id })
                        var fields: [String: JSONValue] = ["start_time": .string(time), "due_date": .string(date)]
                        if existing?.durationMin == nil { fields["duration_min"] = .number(15) }
                        await taskStore.patch(taskId: id, fields: fields) { _ in }
                    }
                }
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
            Toggle(isOn: Binding(get: { vm.filters.showCompleted }, set: { vm.filters.showCompleted = $0 })) {
                Label("Показывать выполненные", systemImage: "checkmark.circle")
            }

            Menu {
                if projectStore.projects.isEmpty { Text("Нет проектов") }
                else {
                    ForEach(projectStore.projects) { project in
                        filterOption(project.name, selected: vm.visibleProjectIds[project.id] == true) {
                            vm.toggleVisibleProject(project.id)
                        }
                    }
                }
            } label: { Label("Показывать в разделе", systemImage: "eye") }

            if vm.filters.isActive {
                Divider()
                Button(role: .destructive) { vm.filters = .empty } label: {
                    Label("Сбросить фильтры", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            TFPlannerToolbarIcon(systemName: "slider.horizontal.3", tint: vm.filters.isActive ? .tfRed : .tfSub)
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
}

private struct TodaySectionTaskID: Identifiable {
    let id: String
}
