import SwiftUI
import os

// «Задачи проекта» — spec/SCREENS-2.md §8, `/projects/:id`. Сверено построчно
// с живым `src/screens/ProjectTasksScreen.tsx` 31.08.2026.
//
// ⚠️ КОНТРАКТНАЯ ДЫРА (не мой файл чинить, в отчёте оркестратору): «+» в
// шапке в вебе ведёт на `/task/new?project=id` — с предзаполненным проектом.
// `AppRoute.taskCreate` пока не несёт `projectID`, поля
// «проект» там нет — веду на пустую форму без предзаполнения, пользователь
// выберет проект вручную.
//
// Кнопка «Документация» (`ProjectNotesSection`) раньше вела на голый `.notes`
// без параметра — так же, как в вебе, но там это не мешало (веб-код умеет
// подсветить нужную папку иначе). На native это выглядело как переход в
// произвольный несвязанный корень Дневника — просьба владельца 03.09.2026
// («переносит не туда, куда надо»). Заведён `AppRoute.noteFolder(folderID:)`
// сверх контракта (`.notes` без параметра не тронут) — `NotesScreen` теперь
// умеет открыться сразу на нужной папке.
struct ProjectTasksScreen: View {
    /// `nil` — общий список всех задач, включая задачи без проекта.
    let projectID: String?
    @Environment(ProjectStore.self) private var projectStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @State private var relationshipTasks: [ApiTask] = []

    private let apiClient = APIClient()
    private let logger = Logger(subsystem: "com.taskflow.apiclient", category: "project-tasks")

    @State private var pendingDetail: String?
    /// Раскрытые родительские задачи (шеврон слева у строки). Дочерние берутся
    /// из `relationshipTasks` — там лежит весь список с потомками.
    @State private var expandedIDs: Set<String> = []
    /// Фильтр списка; помнится по проекту.
    @State private var filter: ProjectTaskFilter = .open
    private var showsAllProjects: Bool { projectID == nil }
    private var isStatusFilter: Bool { showsAllProjects && [.working, .review, .blocked, .waiting].contains(filter) }
    private var availableFilters: [ProjectTaskFilter] {
        // Пункта «Выполненные» и «Все, включая выполненные» больше нет:
        // закрытые карточки живут в архиве (владелец 01.11.2026).
        showsAllProjects
            ? ProjectTaskFilter.allTasksCases
            : ProjectTaskFilter.allCases.filter { $0 != .waiting && $0 != .blocked && $0 != .all }
    }
    private var filterKey: String {
        showsAllProjects ? "all-projects.filter" : "project.filter.\(projectID ?? "all")"
    }

    @State private var showNewTask = false

    /// На проектах владелец — создатель проекта (он же владелец трекера).
    /// В этой роли доступны контекстные свайпы. Постоянное true, пока
    /// авторизация владельца не появится отдельным состоянием.
    private var isTaskOwner: Bool { true }

    /// Приватный проект скрыт от агентов; переключает только владелец (сервер иначе даст 403).
    private func setPrivate(_ value: Bool, for project: ApiProject) async {
        do {
            _ = try await apiClient.patchProject(id: project.id, fields: ["is_private": .bool(value)])
            await projectStore.load()
        } catch {
            logger.error("is_private: \(error.localizedDescription)")
        }
    }

    private var project: ApiProject? {
        guard let projectID else { return nil }
        return projectStore.projects.first { $0.id == projectID }
    }

    /// Закреплённые — единым блоком сверху, порядок внутри каждой группы не
    /// трогаем (два `filter`, НЕ `sorted(by:)` — `Array.sort` в Swift не
    /// гарантированно стабилен, а спека и веб-код требуют стабильность).
    private var tasks: [ApiTask] {
        let source = relationshipTasks.isEmpty ? taskStore.tasks : relationshipTasks
        // Общий список включает задачи с проектом и без него.
        let inScope: (ApiTask) -> Bool = { showsAllProjects || $0.projectId == projectID }
        if isStatusFilter {
            // Каждая карточка попадает ровно в один статус. Родителя с другим
            // состоянием не добавляем как контекст: это нарушило бы исключительность.
            let matched = source.filter(filter.matches)
            return matched.filter { $0.pinned } + matched.filter { !$0.pinned }
        }
        if filter != .open {
            // Фильтр по состоянию: корень остаётся, если подходит он сам или кто-то из потомков.
            let byParent = Dictionary(grouping: source, by: \.parentId)
            func hit(_ t: ApiTask) -> Bool {
                filter.matches(t) || (byParent[t.id] ?? []).contains(where: hit)
            }
            let scoped = source.filter { inScope($0) && $0.parentId == nil && hit($0) }
            return scoped.filter { $0.pinned } + scoped.filter { !$0.pinned }
        }
        // Закрытая карточка уходит из списка целиком, даже если у неё остались
        // неотмеченные шаги: сервер закрывает карточку сам, шаги при этом не
        // отмечает, и она торчала в проекте зачёркнутой (владелец 12.10.2026).
        var openTreeIDs = Set(source.lazy.filter { $0.status == .active }.map(\.id))

        // Поднимаем признак открытой работы по всей цепочке родителей. В
        // проектном списке остаются только корневые задачи, а потомки живут в
        // разделе «Связанные задачи» — без дублирования на одном уровне.
        var didAddParent = true
        while didAddParent {
            didAddParent = false
            for task in source where openTreeIDs.contains(task.id) {
                if let parentID = task.parentId, openTreeIDs.insert(parentID).inserted {
                    didAddParent = true
                }
            }
        }

        let scoped = source.filter { task in
            inScope(task) && task.parentId == nil && openTreeIDs.contains(task.id)
        }
        return scoped.filter { $0.pinned } + scoped.filter { !$0.pinned }
    }

    private var notFound: Bool {
        projectID != nil && !projectStore.isLoading && projectStore.errorMessage == nil && project == nil
    }

    /// Заголовок шапки. «Все задачи» — режим обхода проектов, там названия
    /// проекта нет по определению.
    private var screenTitle: String {
        if showsAllProjects { return "Все задачи" }
        return project?.name ?? "Проект"
    }

    private var emptyText: String {
        if filter != .open && filter != .all { return "Нет задач с выбранным статусом" }
        if showsAllProjects { return "Задач нет" }
        return "В проекте пока нет задач"
    }

    var body: some View {
        List {
            Group {
                TFErrorBanner(projectStore.errorMessage, variant: .inline)
                TFErrorBanner(taskStore.errorMessage, variant: .inline)

                if projectStore.isLoading || taskStore.isLoading { TFLoading(.block) }

                if notFound {
                    notFoundView
                } else if projectID == nil || project != nil {
                    if tasks.isEmpty && !projectStore.isLoading && !taskStore.isLoading {
                        TFEmptyState(
                            icon: "tray",
                            text: emptyText
                        )
                        .padding(.horizontal, TFSpacing.xs)
                    } else {
                        Group {
                            ForEach(tasks.indices, id: \.self) { rowIndex in
                                rowWithIndex(rowIndex)
                            }
                        }
                    }

                    if let project {
                        ProjectNotesSection(project: project, onProjectPatched: { _ in
                            Task { await projectStore.load() }
                        })
                    }
                }

            }
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await taskStore.load(silent: true)
            await refreshRelationshipTasks()
        }
        .background(Color.tfBackground)
        // Штатная шапка (просьба владельца 03.09.2026 — «нативные кнопки
        // везде одним элементом»). Была `DirectoryCompactHeader` (свой
        // ZStack) ради цветного кружка проекта перед заголовком —
        // `tfNativeHeader` такого слота не даёт (только `String`), но у
        // toolbar есть штатное место как раз под это: `.principal` меняет
        // содержимое заголовка на произвольное вью, сам разруливая место с
        // соседним «+» (тот самый наезд текста на кнопку, LOCK-060/061,
        // здесь в принципе невозможен на системном toolbar).
        .tfNativeHeader(screenTitle, displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    if let project {
                        Circle().fill(Color(hex: project.color ?? TFHexDefault.unassigned)).frame(width: 10, height: 10)
                    }
                    Text(screenTitle)
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                }
            }
            if project != nil || showsAllProjects {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(availableFilters) { f in
                            Button {
                                filter = f
                                UserDefaults.standard.set(f.rawValue, forKey: filterKey)
                            } label: {
                                if filter == f {
                                    Label(f.title, systemImage: "checkmark")
                                } else {
                                    Label(f.title, systemImage: f.icon)
                                }
                            }
                        }
                        Divider()
                        Button { showNewTask = true } label: {
                            Label("Добавить задачу", systemImage: "plus")
                        }
                        if let project {
                            Button { Task { await setPrivate(!project.isPrivate, for: project) } } label: {
                                Label(project.isPrivate ? "Сделать проект обычным" : "Сделать проект приватным",
                                      systemImage: project.isPrivate ? "eye" : "eye.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Фильтр и действия")
                    .hintAnchor(showsAllProjects ? HintAnchorID.allTasksFilter : "project.tasks.filter")
                }
            }
        }
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: filterKey), let f = ProjectTaskFilter(rawValue: raw), availableFilters.contains(f) { filter = f }
        }
        .task {
            if projectStore.projects.isEmpty { await projectStore.load() }
            if taskStore.tasks.isEmpty { await taskStore.load() }
            await refreshRelationshipTasks()
        }
        .taskCardSheet(taskID: $pendingDetail)
        .onChange(of: pendingDetail) { previous, current in
            if previous != nil, current == nil {
                Task { await refreshRelationshipTasks() }
            }
        }
        .taskCreateFlow(isPresented: $showNewTask)
    }

    private func rowWithIndex(_ rowIndex: Int) -> some View {
        if rowIndex < 0 || rowIndex >= tasks.count {
            logger.error("rowWithIndex out of bounds: index=\(rowIndex) count=\(tasks.count)")
            return AnyView(EmptyView())
        }
        return treeRow(tasks[rowIndex], depth: 0)
    }

    /// Прямые потомки задачи; незакрытые впереди, порядок внутри групп стабильный.
    private func children(of task: ApiTask) -> [ApiTask] {
        if isStatusFilter { return [] }
        let byParent = Dictionary(grouping: relationshipTasks, by: \.parentId)
        func hit(_ t: ApiTask) -> Bool {
            filter.matches(t) || (byParent[t.id] ?? []).contains(where: hit)
        }
        let all = (byParent[task.id] ?? []).filter(hit)
        return all.filter { $0.status != .completed } + all.filter { $0.status == .completed }
    }

    /// Строка задачи + (если раскрыта) её дочерние. Ни шеврона, ни сдвига:
    /// раскрывается тапом по аватару родителя (владелец 06.10.2026), дочерние
    /// идут подряд без разделителей, разделители — между группами.
    private func treeRow(_ task: ApiTask, depth: Int) -> AnyView {
        let shortId = String(task.id.prefix(8))
        let swipeAction = ProjectTaskSwipeAction.action(
            for: task, isOwner: isTaskOwner, currentUserID: session.currentUser?.id
        )
        let kids = children(of: task)
        let isOpen = expandedIDs.contains(task.id) || (filter != .open && filter != .all && !kids.isEmpty)
        return AnyView(
            Group {
                DirectoryTaskRow(
                    index: shortId,
                    task: task,
                    isOwner: isTaskOwner,
                    onOpen: { pendingDetail = task.id },
                    onDelete: { Task { await deleteTask(task) } },
                    swipeAction: swipeAction,
                    onSwipeAction: { Task { await performSwipe(task: task, action: swipeAction) } },
                    onAvatarTap: kids.isEmpty ? nil : {
                        withAnimation(.snappy) {
                            if isOpen { expandedIDs.remove(task.id) } else { expandedIDs.insert(task.id) }
                        }
                    }
                )
                if isOpen {
                    ForEach(kids, id: \.id) { kid in
                        treeRow(kid, depth: depth + 1)
                    }
                }
            }
        )
    }

    /// Удаление строки из проектного списка. `TaskStore.delete` чистит только
    /// `taskStore.tasks`, а строки этого экрана рисуются из
    /// `relationshipTasks` (`tasks(includeChildren: true)`) — из-за этого
    /// удалённая задача оставалась на месте до ручного pull-to-refresh
    /// (владелец 19.09.2026: «после действия не исчезают, сам должен
    /// обновлять»). Гасим строку в обоих источниках и подтягиваем свежий
    /// список, чтобы пересчиталось дерево.
    private func deleteTask(_ task: ApiTask) async {
        _ = await taskStore.delete(taskId: task.id)
        relationshipTasks.removeAll { $0.id == task.id }
        await refreshRelationshipTasks()
    }

    /// Свайп-действие по строке проекта. «Запустить» — сервер поднимает флаг.
    /// Принять ревью — снять блокировку и закрыть задачу (как в TaskDetailViewModel).
    private func performSwipe(task: ApiTask, action: ProjectTaskSwipeAction?) async {
        guard let action else { return }
        do {
            switch action {
            case .complete:
                // complete покрывает «принять задачу» — и ревью, и просто
                // завершить. Если был ревью — сначала снимаем блокировку.
                if task.agentState == .review {
                    try await apiClient.approveCurrentTaskVersion(taskID: task.id)
                    _ = try await apiClient.setTaskAgentState(id: task.id, state: nil, comment: nil)
                }
                _ = try await apiClient.patchTask(id: task.id, fields: ["status": .string("completed")])
            case .restore:
                // Восстановление из архива — экран «Архив», здесь действие
                // невозможно: `action(for:)` для живых задач его не выдаёт.
                break
            }
            await taskStore.load(silent: true)
            await refreshRelationshipTasks()
        } catch {
            // Тихая ошибка: визуально строка просто не изменится. Подробный
            // тост для свайпа не показывается — это быстрый жест, и отдельная
            // обработка ошибок выглядит лишней (как в существующих свайпах).
        }
    }

    private func refreshRelationshipTasks() async {
        relationshipTasks = (try? await apiClient.tasks(includeChildren: true)) ?? []
    }

    private var notFoundView: some View {
        VStack(spacing: TFSpacing.md) {
            Text("Проект не найден — возможно, он удалён.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            NavigationLink(value: AppRoute.projects) {
                Text("К списку проектов")
                    .tfText(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfText)
                    .padding(.horizontal, TFSpacing.lg)
                    .frame(height: 44)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            }
            .buttonStyle(TFTapScaleStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TFSpacing.xl)
    }
}
