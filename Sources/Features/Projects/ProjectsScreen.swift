import SwiftUI

// «Проекты» — spec/SCREENS-2.md §7, `/projects`. Сверено построчно с живым
// `src/screens/ProjectsScreen.tsx` 31.08.2026 (ARCHITECTURE.md правило 3 —
// расходится спека с кодом, верю коду). Правка 03.09.2026 по прямой просьбе
// владельца — см. пункты 1 и 2 ниже.
//
// 1. Шапка — `.tfNativeHeader` (TFNativeHeader.swift), не самодельный
//    `.toolbarBackground(.ultraThinMaterial, ...)`. Старая ручная связка
//    конфликтовала с системным scroll edge effect (iOS 26 рисует блюр по
//    скроллу сама, без единой строчки кода — см. комментарий в
//    TFNativeHeader.swift) и давала серую плашку при прокрутке вверх.
// 2. Управление списком — нативная пара `Menu` в toolbar: фильтр и «…».
//    Создание, поиск и выбор проекта для изменения не занимают отдельные
//    кнопки и остаются доступны без скрытых жестов.
// 3. Пустое состояние — просто строка текста (не `TFEmptyState` с иконкой,
//    как у Меток) — 1:1 с кодом, текст обновлён под новую кнопку.
struct ProjectsScreen: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(TaskStore.self) private var taskStore

    @State private var editingID: String?
    @State private var projectDraft: ProjectDraft?
    @State private var deleteRequest: DirectoryConfirmRequest?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var filter = ProjectFilter.all
    @State private var isSelecting = false
    @State private var selectedProjectIDs: Set<String> = []
    @State private var hasOpenedCreateForm = false
    #if DEBUG
    @State private var cancellationChecked = false
    #endif

    /// Сценарий центрального «+»: список остаётся контекстом формы, но сама
    /// форма открывается сразу, без промежуточного ручного тапа по «…».
    private let opensCreateForm: Bool

    private let apiClient = APIClient()

    init(opensCreateForm: Bool = false) {
        self.opensCreateForm = opensCreateForm
    }

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges — здесь живёт
        // `ProjectEditForm` с текстовым полем, и до фикса под клавиатурой
        // были те же уголки. Создание проекта теперь идёт через `.fullScreenCover`
        // (`QuickAddProjectView`), а не inline в списке.
        ZStack {
        TFScreenFill()
        // Основные разделы находятся вне List: каждая плитка — отдельная ссылка.
        VStack(spacing: 0) {
            if !isSelecting {
                taskSectionsRow
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.top, TFSpacing.sm)
                    .padding(.bottom, TFSpacing.sm)
            }
            List {
                Group {
                    ForEach(visibleProjects) { project in
                    if editingID == project.id {
                        ProjectEditForm(project: project, apiClient: apiClient, onSaved: {
                            editingID = nil
                            Task { await projectStore.load() }
                        }, onCancel: { editingID = nil })
                    } else if isSelecting {
                        selectionRow(project)
                    } else {
                        DirectorySwipeRow(
                            onEdit: { editingID = project.id },
                            onDelete: { requestDelete(project) }
                        ) {
                            projectRow(project)
                        }
                    }
                }

                if projectStore.projects.isEmpty && !projectStore.isLoading && projectDraft == nil {
                    TFEmptyState(
                        icon: "folder",
                        text: "Проектов пока нет — создайте первый через меню «…»"
                    )
                    .padding(.horizontal, TFSpacing.xs)
                } else if visibleProjects.isEmpty && !projectStore.isLoading && projectDraft == nil {
                    Text("Проекты не найдены")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TFSpacing.xs)
                }

                if projectStore.isLoading { TFLoading(.block) }
                #if DEBUG
                if ProcessInfo.processInfo.environment["TASKFLOW_PROJECT_CANCELLATION_TEST"] == "1" {
                    Button("Отменить обновление") {
                        Task {
                            withUnsafeCurrentTask { $0?.cancel() }
                            await projectStore.load()
                            cancellationChecked = true
                        }
                    }.accessibilityIdentifier("projects.test.cancel")
                    if cancellationChecked {
                        Text("Обновление отменено").accessibilityIdentifier("projects.test.cancelled")
                    }
                }
                #endif
                TFErrorBanner(projectStore.errorMessage, variant: .inline)
                TFErrorBanner(errorMessage, variant: .block)

                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        // Штатный pull-to-refresh (iOS 15+). Прокрути вниз и потяни — вызовет
        // projectStore.load(). Сегодня не трогаю по требованию владельца.
        // Задачи тоже: фильтры по состоянию считаются по списку задач, и без
        // него проект с только что перенесённой карточкой оставался скрытым.
            .refreshable { async let projects: Void = projectStore.load(); async let tasks: Void = taskStore.load(silent: true); _ = await (projects, tasks) }
        }
        }
        // Штатная SwiftUI-шапка. Системная стрелка назад добавляется стеком
        // навигации; пару кнопок группирует сам toolbar iOS.
        .tfNativeHeader("Проекты", displayMode: .inline)
        .tfSheet(isPresented: $searchPresented) {
            NavigationStack {
                Form { TextField("Поиск проектов", text: $searchText).accessibilityIdentifier("projects.search.field") }
                    .navigationTitle("Поиск проектов")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { searchPresented = false } } }
            }.presentationDetents([.medium])
        }
        // Шторка создания проекта в стиле quick-add: те же стеклянные/тёплые
        // эффекты, что у задачи (QuickAddTaskView), две иконки в капсуле —
        // цвет и база знаний, кнопка-стрелка при непустом названии, тап по
        // фону закрывает. Полная форма остаётся за `ProjectEditForm`.
        .fullScreenCover(item: $projectDraft) { draft in
            QuickAddProjectView(draft: draft) {
                projectDraft = nil
            } onCancel: {
                projectDraft = nil
            }
            .presentationBackground(.clear)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                projectActionsMenu
            }
        }
        .task {
            if opensCreateForm && !hasOpenedCreateForm {
                hasOpenedCreateForm = true
                openProjectDraft()
            }
            if projectStore.projects.isEmpty { await projectStore.load() }
        }
        .directoryConfirm($deleteRequest)
    }

    private var projectActionsMenu: some View {
        Menu {
            Button { searchPresented = true } label: { Label("Поиск проектов", systemImage: "magnifyingglass") }
            if isSelecting {
                Button(role: .destructive) {
                    requestDeleteSelected()
                } label: {
                    Label("В архив (\(selectedProjectIDs.count))", systemImage: "archivebox")
                }
                .disabled(selectedProjectIDs.isEmpty)

                // Владелец 27.09.2026: закреплять проекты пачкой из режима выбора.
                // Все выбранные уже закреплены — пункт открепляет.
                Button {
                    Task { await pinSelected(!allSelectedPinned) }
                } label: {
                    Label(
                        allSelectedPinned
                            ? "Открепить выбранные (\(selectedProjectIDs.count))"
                            : "Закрепить выбранные (\(selectedProjectIDs.count))",
                        systemImage: allSelectedPinned ? "pin.slash" : "pin"
                    )
                }
                .disabled(selectedProjectIDs.isEmpty)

                Button {
                    endSelection()
                } label: {
                    Label("Завершить выбор", systemImage: "checkmark")
                }
            } else {
                Button {
                    editingID = nil
                    openProjectDraft()
                } label: {
                    Label("Добавить проект", systemImage: "plus")
                }

                Menu {
                    if projectStore.projects.isEmpty {
                        Text("Нет проектов")
                    } else {
                        ForEach(projectStore.projects) { project in
                            Button(project.name) {
                                editingID = project.id
                            }
                        }
                    }
                } label: {
                    Label("Изменить проект", systemImage: "pencil")
                }

                Button {
                    beginSelection()
                } label: {
                    Label("Выбрать проекты", systemImage: "checkmark.circle")
                }
            }
        } label: {
            Image(systemName: isSelecting ? "checkmark.circle.fill" : "ellipsis")
        }
        .accessibilityLabel("Действия с проектами")
    }

    private var visibleProjects: [ApiProject] {
        projectStore.projects.filter { project in
            let queryMatches = searchText.isEmpty
                || project.name.localizedCaseInsensitiveContains(searchText)
            guard queryMatches else { return false }

            let status = ProjectTaskStatusSummary(project: project, tasks: taskStore.tasks)
            switch filter {
            case .all: return true
            case .pinned: return project.pinned
            case .inWork: return status.inWork > 0
            case .review: return status.review > 0
            case .blocked: return status.blocked > 0
            case .completed: return status.total > 0 && status.completed == status.total
            }
        }
    }

    /// Строка проекта — карточка (`ProjectCard`), а не однострочный ряд:
    /// владелец 08.09.2026 попросил видеть в списке жизнь проекта, а не одно
    /// число. Сам ряд остался кнопкой в тот же маршрут и по-прежнему живёт
    /// внутри `DirectorySwipeRow` (правка/удаление свайпом).
    /// Общее число открытых задач независимо от проекта.
    ///
    /// Считается по всему живому набору (с дочерними), а не только по корням:
    /// иначе задача с закрытым родителем не попадала ни в число, ни в список
    /// (владелец 08.11.2026).
    private var allTasksCount: Int {
        let live = TaskVisibility.liveTasks(taskStore.agentWorkTasks)
        let roots = TaskTreeVisibility.visibleRootIDs(live.map { ($0.id, $0.parentId) })
        return live.filter { roots.contains($0.id) && $0.status == .active }.count
    }

    private var archiveCount: Int { taskStore.archivedTasks.count + projectStore.archivedProjects.count }

    /// Две плитки в одну линию — тот же вид, что «В работе» / «На проверке»
    /// в Обзоре, иконки крупнее (владелец 06.10.2026).
    ///
    /// 11.10.2026: после снятия верхней полосы статусов плитки остались
    /// одними наверху — и на фоне карточек проекта выглядели «мизерными».
    /// Значок и подпись теперь одного кегля с остальным содержимым экрана
    /// (`.body`), как у обычной строки раздела.
    private var taskSectionsRow: some View {
        HStack(spacing: TFSpacing.sm) {
            sectionTile(
                route: .allTasks, title: "Все задачи",
                count: allTasksCount, icon: "tray.full", tint: .tfBlue,
                identifier: "projects.tile.allTasks"
            )
            .hintAnchor(HintAnchorID.projectsAllTasks)
            sectionTile(
                route: .taskArchive, title: "Архив",
                count: archiveCount, icon: "archivebox", tint: .tfOrange,
                identifier: "projects.tile.archive"
            )
        }
        .task { await taskStore.loadArchive(); await projectStore.loadArchive() }
    }

    private func sectionTile(route: AppRoute, title: String, count: Int, icon: String, tint: Color, identifier: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: icon)
                    .tfTypeFont(size: 19)
                    .foregroundStyle(tint)
                Text(title).lineLimit(1)
                Text("\(count)").monospacedDigit().foregroundStyle(Color.tfSub)
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(count)")
        .accessibilityIdentifier(identifier)
    }

    private func projectRow(_ project: ApiProject) -> some View {
        NavigationLink(value: AppRoute.projectTasks(projectID: project.id)) {
            ProjectCard(project: project, tasks: taskStore.tasks)
        }
        .buttonStyle(TFTapRowStyle())
    }

    private func selectionRow(_ project: ApiProject) -> some View {
        let selected = selectedProjectIDs.contains(project.id)
        return Button {
            if selected {
                selectedProjectIDs.remove(project.id)
            } else {
                selectedProjectIDs.insert(project.id)
            }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .tfText(.input)
                    .foregroundStyle(selected ? Color.tfRed : Color.tfDim)
                    .accessibilityHidden(true)
                ProjectCard(project: project, tasks: taskStore.tasks)
            }
        }
        .buttonStyle(TFTapRowStyle())
        .accessibilityLabel(selected ? "Отменить выбор проекта \(project.name)" : "Выбрать проект \(project.name)")
    }

    private func beginSelection() {
        editingID = nil
        projectDraft = nil
        searchPresented = false
        selectedProjectIDs.removeAll()
        isSelecting = true
    }

    /// Открывает шторку создания — единая точка входа для центрального «+»
    /// (`opensCreateForm`) и меню «…» → «Добавить проект». Дубль проверки
    /// `projectDraft == nil` защищает от повторного открытия поверх уже
    /// открытой шторки.
    private func openProjectDraft() {
        guard projectDraft == nil else { return }
        projectDraft = ProjectDraft()
    }

    private func endSelection() {
        selectedProjectIDs.removeAll()
        isSelecting = false
    }

    /// Текст confirm-а зависит от `task_count` — прямая цитата `ProjectsScreen.tsx`.
    private func requestDelete(_ project: ApiProject) {
        let count = project.taskCount ?? 0
        deleteRequest = DirectoryConfirmRequest(
            title: "Отправить проект «\(project.name)» в архив?",
            description: count > 0
                ? "Проект и его задачи исчезнут из обычных списков. Их можно вернуть из архива."
                : "Проект можно будет восстановить из архива.",
            confirmLabel: "В архив",
            onConfirm: {
                Task {
                    await projectStore.delete(projectId: project.id)
                }
            }
        )
    }

    private func requestDeleteSelected() {
        let selected = projectStore.projects.filter { selectedProjectIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let openProjects = selected.filter { project in
            let summary = ProjectTaskStatusSummary(project: project, tasks: taskStore.tasks)
            return summary.inWork > 0 || summary.review > 0 || summary.blocked > 0
        }
        guard openProjects.isEmpty else {
            let names = openProjects.prefix(2).map(\.name).joined(separator: ", ")
            let suffix = openProjects.count > 2 ? " и ещё \(openProjects.count - 2)" : ""
            errorMessage = "Пакетное архивирование доступно только для проектов без открытых задач. Сначала закройте задачи в: \(names)\(suffix)."
            return
        }
        let count = selected.count
        let tasksCount = selected.reduce(0) { partial, project in
            partial + (project.taskCount ?? 0) + (project.completedCount ?? 0)
        }
        deleteRequest = DirectoryConfirmRequest(
            title: "Отправить проекты (\(count)) в архив?",
            description: "Проекты и задачи внутри (\(tasksCount)) можно будет восстановить из архива.",
            confirmLabel: "В архив \(count)",
            onConfirm: {
                Task { await deleteSelectedProjects(selected.map(\.id)) }
            }
        )
    }

    private var allSelectedPinned: Bool {
        let selected = projectStore.projects.filter { selectedProjectIDs.contains($0.id) }
        return !selected.isEmpty && selected.allSatisfy(\.pinned)
    }

    private func pinSelected(_ pinned: Bool) async {
        errorMessage = nil
        for id in selectedProjectIDs {
            do {
                _ = try await apiClient.patchProject(id: id, fields: ["pinned": .bool(pinned)])
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                break
            }
        }
        await projectStore.load()
        endSelection()
    }

    private func deleteSelectedProjects(_ ids: [String]) async {
        errorMessage = nil
        for id in ids {
            do {
                try await apiClient.deleteProject(id: id)
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                break
            }
        }
        await projectStore.load()
        let existingIDs = Set(projectStore.projects.map(\.id))
        selectedProjectIDs.formIntersection(existingIDs)
        if selectedProjectIDs.isEmpty { isSelecting = false }
    }
}

private enum ProjectFilter: String, CaseIterable, Identifiable {
    case all, pinned, inWork, review, blocked, completed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Все проекты"
        case .pinned: "Закреплённые"
        case .inWork: "В работе"
        case .review: "На ревью"
        case .blocked: "Заблокированные"
        case .completed: "Все задачи выполнены"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin.fill"
        case .inWork: "play.circle.fill"
        case .review: "eye.fill"
        case .blocked: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }
}

/// Форма создания в стиле quick-add — те же стеклянные/тёплые эффекты, что у
/// задачи (`QuickAddTaskView`). В капсуле отличается только составом
/// инструментов: вместо срока/проекта/приоритета — **цвет и база знаний**.
/// Закрывается тапом по фону (как у задачи). Полная форма правки существующего
/// проекта остаётся за `ProjectEditForm`.
private struct QuickAddProjectView: View {
    @ObservedObject var draft: ProjectDraft
    let onSaved: () -> Void
    let onCancel: () -> Void

    @Environment(ProjectStore.self) private var projectStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var isDatasetPopoverPresented = false

    var body: some View { AnyView(bodyContent) }

    @ViewBuilder private var bodyContent: some View {
        Group {
            if #available(iOS 26.0, *) {
                systemQuickAdd
            } else {
                legacyQuickAdd
            }
        }
        .alert("Не удалось создать проект", isPresented: Binding(
            get: { projectStore.errorMessage != nil },
            set: { if !$0 { projectStore.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { projectStore.errorMessage = nil }
        } message: {
            Text(projectStore.errorMessage ?? "")
        }
        .task {
            isNameFocused = true
        }
    }

    @available(iOS 26.0, *)
    private var systemQuickAdd: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDatasetPopoverPresented else { return }
                    closePanel()
                }
                .safeAreaBar(edge: .bottom) {
                    card(systemAppearance: true)
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                        .tint(Color.primary)
                        .padding(.horizontal, TFSpacing.md)
                        .padding(.bottom, TFSpacing.sm)
                }
        }
    }

    private var legacyQuickAdd: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.1))
                .ignoresSafeArea()
                .onTapGesture {
                    guard !isDatasetPopoverPresented else { return }
                    closePanel()
                }

            card(systemAppearance: false)
                .background(Color.tfCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
                .padding(.horizontal, TFSpacing.md)
                .padding(.bottom, TFSpacing.sm)
        }
    }

    private static let warmGlow = Color(red: 1.0, green: 0.84, blue: 0.6)

    private func card(systemAppearance: Bool) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TextField("Название проекта", text: $draft.name, axis: .vertical)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .lineLimit(1...3)
                .focused($isNameFocused)

            HStack(spacing: TFSpacing.xs) {
                toolsScroll(systemAppearance: systemAppearance)

                if draft.isSaveEnabled {
                    primaryActionButton(systemAppearance: systemAppearance)
                }
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.sm)
    }

    @ViewBuilder
    private func toolsScroll(systemAppearance: Bool) -> some View {
        if systemAppearance {
            ScrollView(.horizontal, showsIndicators: false) {
                toolsCapsule(slot: TFHitTarget.min, systemAppearance: true)
                    .background(ProjectScrollBounceDisabler())
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                toolsCapsule(slot: TFHitTarget.min, systemAppearance: false)
                    .background(ProjectScrollBounceDisabler())
            }
            .clipShape(Capsule())
        }
    }

    private func toolsCapsule(slot: CGFloat, systemAppearance: Bool) -> some View {
        HStack(spacing: 0) {
            Menu {
                DirectoryColorSwatches(
                    colors: DirectoryColors.project,
                    selected: $draft.colorHex,
                    size: 28
                )
                .padding(.vertical, TFSpacing.xs)
            } label: {
                quickIcon(
                    slot: slot,
                    "paintpalette",
                    isSet: draft.colorHex != DirectoryColors.project.first,
                    systemAppearance: systemAppearance,
                    swatch: Color(hex: draft.colorHex)
                )
            }
            .accessibilityLabel("Цвет проекта")
            .accessibilityValue("Текущий цвет")

            Button { isDatasetPopoverPresented = true } label: {
                quickIcon(
                    slot: slot,
                    "book.closed",
                    isSet: draft.datasetId != nil,
                    systemAppearance: systemAppearance
                )
            }
            .accessibilityLabel("База знаний")
            .accessibilityValue(datasetLabel)
            .popover(isPresented: $isDatasetPopoverPresented) {
                KnowledgeDatasetPicker(selection: $draft.datasetId)
                    .padding(TFSpacing.lg)
                    .frame(width: 320)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.regularMaterial)
            }
        }
        .buttonStyle(TFTapScaleStyle())
        .padding(.horizontal, systemAppearance ? 0 : TFSpacing.xs)
        .background {
            if !systemAppearance {
                Capsule()
                    .fill(Color.tfBackground)
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.55), lineWidth: 3)
                            .blur(radius: 2.5)
                            .offset(y: 1.5)
                            .mask(Capsule().fill(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)))
                    }
                    .overlay {
                        Capsule().fill(
                            LinearGradient(
                                colors: [.clear, Self.warmGlow.opacity(0.14)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                    }
                    .overlay {
                        Capsule()
                            .stroke(Self.warmGlow.opacity(0.45), lineWidth: 2.5)
                            .blur(radius: 3)
                            .offset(y: -2)
                            .mask(Capsule().fill(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)))
                    }
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
            }
        }
    }

    @ViewBuilder
    private func quickIcon(slot: CGFloat, _ systemImage: String, isSet: Bool, systemAppearance: Bool, swatch: Color? = nil) -> some View {
        if systemAppearance {
            ZStack {
                if let swatch, isSet {
                    Circle()
                        .fill(swatch)
                        .frame(width: 14, height: 14)
                }
                Image(systemName: systemImage)
                    .symbolVariant(isSet && swatch == nil ? .fill : .none)
                    .tfTypeFont(size: TFIconSize.sm)
                    .foregroundStyle(isSet ? Color.tfRed : Color.tfSub)
            }
            .frame(width: slot, height: slot)
        } else {
            ZStack {
                if let swatch, isSet {
                    Circle()
                        .fill(swatch)
                        .frame(width: 12, height: 12)
                }
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: isSet && swatch == nil
                                ? [Color.tfRed.opacity(0.7), Color.tfRed]
                                : [Color.tfSub.opacity(0.55), Color.tfText.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.9), radius: 1, y: -1)
                    .shadow(color: Self.warmGlow.opacity(0.5), radius: 2, y: 1.5)
                    .opacity(swatch != nil && isSet ? 0.0 : 1.0)
            }
            .frame(width: slot, height: slot)
        }
    }

    @ViewBuilder
    private func primaryActionButton(systemAppearance: Bool) -> some View {
        if #available(iOS 26.0, *), systemAppearance {
            Button(action: save) {
                Image(systemName: "arrow.up")
                    .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Создать проект")
        } else {
            Button(action: save) {
                Image(systemName: "arrow.up")
                    .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                    .foregroundStyle(Color.tfPaper)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(Color.tfRed)
                            .overlay {
                                Circle().fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                                    .mask(
                                        Circle().fill(
                                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center)
                                        )
                                    )
                            }
                            .shadow(color: .black.opacity(0.5), radius: 7, y: 4)
                            .shadow(color: Color.tfRed.opacity(0.45), radius: 10, y: 2)
                    }
                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Создать проект")
        }
    }

    private var datasetLabel: String {
        // Без загруженного списка датасетов даём короткую подпись «по умолчанию».
        draft.datasetId == nil ? "Общая база" : "Выбран датасет"
    }

    private func closePanel() {
        isNameFocused = false
        dismiss()
    }

    private func save() {
        guard draft.isSaveEnabled else { return }
        isNameFocused = false
        Task {
            let created = await projectStore.create(
                name: draft.name.trimmingCharacters(in: .whitespaces),
                color: draft.colorHex,
                withDocs: true,
                knowledgeDatasetId: draft.datasetId
            )
            if created != nil {
                onSaved()
            }
        }
    }
}

/// Локальное состояние черновика создания проекта — тот же объект, что у
/// `QuickAddTaskView` через `QuickAddDraft` (`RootShellView.swift`). Хранится
/// здесь же, потому что форма живёт только в этом файле и не нужна снаружи.
final class ProjectDraft: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String = ""
    @Published var colorHex: String = DirectoryColors.project.first ?? "#4A9FD8"
    @Published var datasetId: String?

    var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Гасит «резинку» горизонтального скролла капсулы инструментов. Тот же
/// приём, что в `QuickAddTaskView` — SwiftUI своего API не даёт, и пустая
/// UIKit-вьюха снимает `bounces` у ближайшего `UIScrollView` вверх по
/// иерархии. Имя с префиксом, потому что в `QuickAddTaskView.swift` уже
/// живёт `private struct ScrollBounceDisabler` с тем же телом — отдельный
/// публичный там не оправдан.
struct ProjectScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var candidate: UIView? = uiView.superview
            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceHorizontal = false
                    return
                }
                candidate = current.superview
            }
        }
    }
}

/// Инлайн-форма правки — разворачивается на месте строки: название,
/// системный `ColorPicker`, закрепление, база знаний и сохранение. Своим `APIClient()`
/// зовёт `patchProject` — `ProjectStore` метода `update` не даёт (Core чужой),
/// после успеха родитель перезагружает стор, чтобы кэш не разъехался с сервером.
private struct ProjectEditForm: View {
    let project: ApiProject
    let apiClient: APIClient
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: Color
    @State private var pinned: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Полка базы знаний. `nil` — общая база TaskFlow.
    @State private var datasetId: String?
    /// Текст предупреждения от сервера (409): сколько документов переедет и
    /// сколько примерно займёт переиндексация. Пока он не пуст — показан
    /// диалог, и до ответа владельца ничего не сохраняется.
    @State private var reindexPrompt: String?

    init(project: ApiProject, apiClient: APIClient, onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.apiClient = apiClient
        self.onSaved = onSaved
        self.onCancel = onCancel
        _name = State(initialValue: project.name)
        _color = State(initialValue: Color(hex: project.color ?? TFHexDefault.unassigned))
        _pinned = State(initialValue: project.pinned)
        _datasetId = State(initialValue: project.knowledgeDatasetId)
    }

    var body: some View {
        TFCard(padding: TFSpacing.lg, surface: .card, radius: TFRadius.xl) {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                TFCard(padding: 0, surface: .card2, radius: TFRadius.lg) {
                    TextField("Название проекта", text: $name)
                        .tfText(.input)
                        .foregroundStyle(Color.tfText)
                        .padding(.horizontal, TFSpacing.sm + 4)
                        .padding(.vertical, TFSpacing.sm + 2)
                }

                HStack {
                    ColorPicker("Цвет проекта", selection: $color, supportsOpacity: false)
                    Button {
                        pinned.toggle()
                    } label: {
                        Label(
                            pinned ? "Открепить проект" : "Закрепить проект",
                            systemImage: pinned ? "pin.slash" : "pin"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(pinned ? "Открепить проект" : "Закрепить проект")
                }

                KnowledgeDatasetPicker(
                    selection: $datasetId,
                    reindexWarning: datasetChanged && documentCount > 0
                        ? "Смена базы знаний = переиндексация: \(documentCount) док. уедут "
                          + "в другую базу и будут посчитаны заново. Это займёт время, и "
                          + "пока идёт индексация, эти документы в поиске не находятся."
                        : nil
                )

                TFErrorBanner(errorMessage, variant: .block)

                HStack(spacing: TFSpacing.sm) {
                    TFCard(padding: 0, surface: .card2, radius: TFRadius.lg) {
                        Button("Отмена", action: onCancel)
                            .buttonStyle(TFTapRowStyle())
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .tfText(.row)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tfSub)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "Сохраняем…" : "Сохранить")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .tfText(.row)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tfPaper)
                            .background(Color.tfRedSolid)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapFadeStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
            }
        }
        // Текст диалога — тот, что прислал сервер: там точное число
        // документов и оценка минут, а не догадка клиента.
        .confirmationDialog(
            "Переиндексация",
            isPresented: Binding(
                get: { reindexPrompt != nil },
                set: { if !$0 { reindexPrompt = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Перенести и переиндексировать", role: .destructive) {
                Task { await save(confirmReindex: true) }
            }
            Button("Отмена", role: .cancel) { reindexPrompt = nil }
        } message: {
            Text(reindexPrompt ?? "")
        }
    }

    /// Документов у проекта — из карточки (`docs_count`). Нужно, чтобы не
    /// пугать предупреждением там, где переносить нечего.
    private var documentCount: Int { project.docsCount ?? 0 }

    private var datasetChanged: Bool { datasetId != project.knowledgeDatasetId }

    private func save(confirmReindex: Bool = false) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        var fields: [String: JSONValue] = [
            "name": .string(trimmed),
            "color": .string(color.toHex()),
            "pinned": .bool(pinned),
        ]
        // Датасет шлём только когда он реально поменялся: лишнее поле в теле
        // заставило бы сервер считать это сменой и требовать подтверждения.
        if datasetChanged {
            fields["knowledge_dataset_id"] = datasetId.map { JSONValue.string($0) } ?? .null
            if confirmReindex { fields["confirm_reindex"] = .bool(true) }
        }

        do {
            _ = try await apiClient.patchProject(id: project.id, fields: fields)
            reindexPrompt = nil
            onSaved()
        } catch APIError.conflict(let message) {
            // 409 — сервер ничего не записал и просит подтверждения; в
            // сообщении уже есть число документов и оценка времени.
            reindexPrompt = message
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось переименовать проект"
        }
    }
}
