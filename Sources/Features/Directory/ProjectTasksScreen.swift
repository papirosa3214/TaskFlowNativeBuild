import SwiftUI

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
    let projectID: String

    @Environment(ProjectStore.self) private var projectStore
    @Environment(TaskStore.self) private var taskStore
    @State private var relationshipTasks: [ApiTask] = []

    private let apiClient = APIClient()

    @State private var pendingDetail: String?

    private struct TaskRef: Identifiable {
        let id: String
    }
    @State private var showNewTask = false

    /// На проектах владелец — создатель проекта (он же владелец трекера).
    /// В этой роли доступны контекстные свайпы. Постоянное true, пока
    /// авторизация владельца не появится отдельным состоянием.
    private var isTaskOwner: Bool { true }

    private var project: ApiProject? {
        projectStore.projects.first { $0.id == projectID }
    }

    /// Закреплённые — единым блоком сверху, порядок внутри каждой группы не
    /// трогаем (два `filter`, НЕ `sorted(by:)` — `Array.sort` в Swift не
    /// гарантированно стабилен, а спека и веб-код требуют стабильность).
    private var tasks: [ApiTask] {
        let source = relationshipTasks.isEmpty ? taskStore.tasks : relationshipTasks
        var openTreeIDs = Set(source.lazy.filter { task in
            task.status == .active || task.subtasks.contains { !$0.done }
        }.map(\.id))

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
            task.projectId == projectID && task.parentId == nil && openTreeIDs.contains(task.id)
        }
        return scoped.filter { $0.pinned } + scoped.filter { !$0.pinned }
    }

    private var notFound: Bool {
        !projectStore.isLoading && projectStore.errorMessage == nil && project == nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                TFErrorBanner(projectStore.errorMessage, variant: .inline)
                TFErrorBanner(taskStore.errorMessage, variant: .inline)

                if projectStore.isLoading || taskStore.isLoading { TFLoading(.block) }

                if notFound {
                    notFoundView
                } else if let project {
                    if tasks.isEmpty {
                        TFEmptyState(
                            icon: "tray",
                            text: "В проекте пока нет задач"
                        )
                        .padding(.horizontal, TFSpacing.xs)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(tasks.indices, id: \.self) { rowIndex in
                                rowWithIndex(rowIndex)
                            }
                        }
                    }

                    ProjectNotesSection(project: project, onProjectPatched: { _ in
                        Task { await projectStore.load() }
                    })
                }
            }
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
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
        .tfNativeHeader(project?.name ?? "Проект", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    if let project {
                        Circle().fill(Color(hex: project.color ?? TFHexDefault.unassigned)).frame(width: 10, height: 10)
                    }
                    Text(project?.name ?? "Проект")
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                }
            }
            if project != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewTask = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить")
                }
            }
        }
        .task {
            if projectStore.projects.isEmpty { await projectStore.load() }
            if taskStore.tasks.isEmpty { await taskStore.load() }
            await refreshRelationshipTasks()
        }
        .sheet(item: Binding(
            get: { pendingDetail.map(TaskRef.init) },
            set: { pendingDetail = $0?.id }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: pendingDetail) { previous, current in
            if previous != nil, current == nil {
                Task { await refreshRelationshipTasks() }
            }
        }
        .navigationDestination(isPresented: $showNewTask) { routeDestination(.taskCreate) }
    }

    @ViewBuilder
    private func rowWithIndex(_ rowIndex: Int) -> some View {
        let task = tasks[rowIndex]
        let shortId = String(task.id.prefix(8))
        let swipeAction = ProjectTaskSwipeAction.action(for: task, isOwner: isTaskOwner)
        DirectoryTaskRow(
            index: shortId,
            task: task,
            isOwner: isTaskOwner,
            onOpen: { pendingDetail = task.id },
            onDelete: { Task { await taskStore.delete(taskId: task.id) } },
            swipeAction: swipeAction,
            onSwipeAction: { Task { await performSwipe(task: task, action: swipeAction) } }
        )
    }

    /// Свайп-действие по строке проекта. Поднять флаг — PATCH ready_for_pickup.
    /// Принять ревью — снять блокировку и закрыть задачу (как в TaskDetailViewModel).
    private func performSwipe(task: ApiTask, action: ProjectTaskSwipeAction?) async {
        guard let action else { return }
        do {
            switch action {
            case .markReadyForPickup:
                _ = try await apiClient.patchTask(id: task.id, fields: ["ready_for_pickup": .bool(true)])
            case .complete:
                // complete покрывает «принять задачу» — и ревью, и просто
                // завершить. Если был ревью — сначала снимаем блокировку.
                if task.agentState == .review {
                    try await apiClient.approveCurrentTaskVersion(taskID: task.id)
                    _ = try await apiClient.setTaskAgentState(id: task.id, state: nil, comment: nil)
                }
                _ = try await apiClient.patchTask(id: task.id, fields: ["status": .string("completed")])
            }
            await taskStore.load(silent: true)
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
