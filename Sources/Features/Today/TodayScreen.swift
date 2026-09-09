import SwiftUI

// «Сегодня» (`/today`) — spec/SCREENS-1.md §5.1. Имя структуры и параметры
// (никаких) — контракт `spec/INTEGRATION.md`.
struct TodayScreen: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(SessionStore.self) private var session

    @State private var vm = TodayViewModel()
    @State private var route: AppRoute?
    /// Открытие задачи с «Сегодня» — родная шторка (detents), не пуш через
    /// `route`. Обёртка нужна: `String` в этом проекте не `Identifiable`.
    @State private var sheetTaskID: TappedTaskID?
    @State private var rescheduleOpen = false
    /// Конкретная задача, перенесённая через свайп — открывает RescheduleSheet
    /// именно для неё. Приоритет над `rescheduleOpen` (тот для группы
    /// просроченных с доски).
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
        ScrollView {
                VStack(spacing: 0) {
                if c.trueEmpty && vm.layout == .list {
                    TodayEmptyIllustration()
                } else {
                    // Полоска проектов с «плюсом» убрана по просьбе владельца
                    // (01.09.2026): тот же выбор проектов ежедневника уже есть
                    // в шторке фильтров, а сверху списка он только занимал
                    // место — «это всё есть в фильтре, зачем это наверху».
                    // Сам компонент `PlannerProjectChips` оставлен: выбор
                    // никуда не делся, просто попадают в него теперь фильтром.
                    // Спиннер только на первой загрузке: при обновлении уже
                    // показанного списка он вставлялся сверху и сдвигал ленту.
                    if taskStore.isLoading && taskStore.tasks.isEmpty {
                        TFLoading(.block)
                    }
                    TFErrorBanner(taskStore.errorMessage, variant: .inline)
                        .padding(.horizontal, TFSpacing.lg)

                    Group {
                        switch vm.layout {
                        case .list:
                            TodayListView(
                                waitingTasks: c.waitingTasks, overdueTasks: c.overdueTasks, todayTasks: c.todayTasks,
                                today: today,
                                onOpen: { sheetTaskID = TappedTaskID(id: $0.id) },
                                onComplete: { task in Task { await taskStore.patch(taskId: task.id, fields: ["status": .string("completed")]) { _ in } } },
                                onRescheduleOverdue: { rescheduleOpen = true },
                                onDelete: { task in Task { await taskStore.delete(taskId: task.id) } }
                            )
                            // Без горизонтальных полей: строка задачи идёт во
                            // ВСЮ ширину экрана, как в вебе (там у контейнера
                            // строки `-mx-4`, гасящий поля списка), а отступы
                            // живут внутри самой строки. Поля на списке
                            // превращали строку в узкую полоску.
                        case .board:
                            TodayBoardView(
                                columns: c.boardColumns,
                                onOpenTask: { sheetTaskID = TappedTaskID(id: $0) },
                                onReschedule: { rescheduleOpen = true },
                                onAddTask: { route = .taskCreate }
                            )
                            .padding(.top, TFSpacing.sm)
                        case .hours:
                            TodayHoursView(
                                day: c.hourDays[0],
                                projectColor: { task in
                                    guard let id = task.projectId, let project = projectStore.projects.first(where: { $0.id == id }) else {
                                        return Color(hex: TFHexDefault.unassigned)
                                    }
                                    return Color(hex: project.color ?? TFHexDefault.unassigned)
                                },
                                onOpenTask: { sheetTaskID = TappedTaskID(id: $0) },
                                onSchedule: { id, date, time in
                                    Task {
                                        let existing = taskStore.tasks.first(where: { $0.id == id })
                                        var fields: [String: JSONValue] = ["start_time": .string(time), "due_date": .string(date)]
                                        if existing?.durationMin == nil { fields["duration_min"] = .number(15) }
                                        await taskStore.patch(taskId: id, fields: fields) { _ in }
                                    }
                                },
                                onPrevDay: { vm.hourDateOffset -= 1 },
                                onNextDay: { vm.hourDateOffset += 1 }
                            )
                            .padding(.horizontal, TFSpacing.lg)
                            .padding(.top, TFSpacing.sm)
                        }
                    }
                }
                }
                // Отступ под панель вкладок теперь общий, из RootShellView
                // (safeAreaInset) — свой убран, было бы задвоение.
                .padding(.bottom, TFSpacing.lg)
        }
        .background(Color.tfBackground.ignoresSafeArea())
        .tfNativeHeader(TodayDate.formatWeekdayLabel(headerDate))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu(c: c)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Вид", selection: Binding(get: { vm.layout }, set: { vm.layout = $0 })) {
                        Label("Список", systemImage: "list.bullet").tag(TodayLayout.list)
                        Label("Доска", systemImage: "square.grid.2x2").tag(TodayLayout.board)
                        Label("Один день", systemImage: "calendar").tag(TodayLayout.hours)
                    }
                    .pickerStyle(.inline)
                    Button { route = .search } label: { Label("Поиск", systemImage: "magnifyingglass") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Вид")
                .accessibilityIdentifier("today.view-switcher")
            }
        }
        .navigationDestination(item: $route) { routeDestination($0) }
        .sheet(item: $sheetTaskID) { wrapped in
            NavigationStack {
                TaskFormScreen(taskID: wrapped.id)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible) // родной хендл шторки, свой больше не рисуем
            .presentationCornerRadius(TFRadius.sheet)
            // Промежуточный тон между tfBackground (#171717) и tfCard (#242424,
            // цвет внутренних карточек) — контраст карточек к фону шторки был
            // слишком жёсткий. Общие токены не трогаю — они на весь интерфейс.
            .presentationBackground(Color.tfSheetBackground)
        }
        .task { await vm.loadAgentsIfNeeded() }
        .tfBottomSheet(isPresented: $rescheduleOpen, title: "Срок") {
            RescheduleSheetContent(
                taskIds: rescheduleTask.map { [$0.id] } ?? c.overdueTasks.map(\.id),
                taskStore: taskStore,
                onClose: {
                    rescheduleTask = nil
                    rescheduleOpen = false
                }
            )
        }
        // Сбросить rescheduleTask при ЛЮБОМ закрытии шторки (включая свайп вниз,
        // когда onClose не вызывается). Иначе следующее групповое «Перенести
        // просроченные» применится к одной задаче вместо группы.
        .onChange(of: rescheduleOpen) { _, open in
            if !open { rescheduleTask = nil }
        }
    }

    private var headerDate: String { vm.layout == .hours ? activeHourDate : today }
    /// Нативное системное меню — тот же presentation и стеклянный материал,
    /// что у соседнего меню «…». Никаких `.sheet` и кастомной карточки.
    private func filterMenu(c: TodayComputation) -> some View {
        Menu {
            Menu {
                filterOption("Все проекты", selected: vm.filters.projectId == nil) {
                    vm.filters.projectId = nil
                }
                if c.projectOptions.isEmpty {
                    Text("Нет задач с проектом")
                } else {
                    ForEach(c.projectOptions) { option in
                        filterOption(option.label, selected: vm.filters.projectId == option.id) {
                            vm.filters.projectId = option.id
                        }
                    }
                }
            } label: {
                Label("Проект", systemImage: "folder")
            }

            Menu {
                filterOption("Все метки", selected: vm.filters.labelId == nil) {
                    vm.filters.labelId = nil
                }
                if c.labelOptions.isEmpty {
                    Text("Нет задач с метками")
                } else {
                    ForEach(c.labelOptions) { option in
                        filterOption(option.label, selected: vm.filters.labelId == option.id) {
                            vm.filters.labelId = option.id
                        }
                    }
                }
            } label: {
                Label("Метка", systemImage: "tag")
            }

            Menu {
                filterOption("Все исполнители", selected: vm.filters.assigneeKey == nil) {
                    vm.filters.assigneeKey = nil
                }
                if c.assigneeOptions.hasUnassigned {
                    filterOption("Без исполнителя", selected: vm.filters.assigneeKey == "__none") {
                        vm.filters.assigneeKey = "__none"
                    }
                }
                if c.assigneeOptions.list.isEmpty && !c.assigneeOptions.hasUnassigned {
                    Text("Нет данных об исполнителях")
                } else {
                    ForEach(c.assigneeOptions.list) { option in
                        filterOption(option.name, selected: vm.filters.assigneeKey == option.id) {
                            vm.filters.assigneeKey = option.id
                        }
                    }
                }
            } label: {
                Label("Исполнитель", systemImage: "person")
            }

            Divider()

            Toggle(isOn: Binding(
                get: { vm.filters.showCompleted },
                set: { vm.filters.showCompleted = $0 }
            )) {
                Label("Показывать выполненные", systemImage: "checkmark.circle")
            }

            Menu {
                if projectStore.projects.isEmpty {
                    Text("Нет проектов")
                } else {
                    // «Все проекты» одним тапом — см. TodayViewModel.
                    filterOption(
                        "Все проекты",
                        selected: vm.allProjectsVisible(projectStore.projects.map(\.id))
                    ) {
                        vm.toggleAllVisibleProjects(projectStore.projects.map(\.id))
                    }
                    Divider()
                    ForEach(projectStore.projects) { project in
                        filterOption(
                            project.name,
                            selected: vm.visibleProjectIds[project.id] == true
                        ) {
                            vm.toggleVisibleProject(project.id)
                        }
                    }
                }
            } label: {
                Label("Показывать в разделе", systemImage: "eye")
            }
            // Множественный выбор — меню остаётся открытым (см. UpcomingScreen).
            .menuActionDismissBehavior(.disabled)

            if vm.filters.isActive {
                Divider()
                Button(role: .destructive) { vm.filters = .empty } label: {
                    Label("Сбросить фильтры", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            TFPlannerToolbarIcon(
                systemName: "line.3.horizontal.decrease",
                tint: vm.filters.isActive ? .tfRed : .tfSub
            )
            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
        }
        .accessibilityLabel("Фильтры")
        .accessibilityIdentifier("today.filters")
    }

    private func filterOption(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// Обёртка для `.sheet(item:)` открытия задачи с «Сегодня» — `String` в
/// проекте не `Identifiable`, нужен минимальный wrapper.
private struct TappedTaskID: Identifiable {
    let id: String
}
