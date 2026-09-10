import SwiftUI

/// Два режима задачи во всём приложении: компактная панель
/// `QuickAddTaskView` для создания и одна плоская системная шторка для
/// существующей задачи. Все поля в готовой задаче активны сразу.
struct TaskFormScreen: View {
    let taskID: String?

    private enum LinkedTaskNavigation: Identifiable, Hashable {
        case detail(String)
        case create(parentID: String, parentTitle: String, projectID: String?)

        var id: String {
            switch self {
            case .detail(let id): "detail-\(id)"
            case .create(let parentID, _, _): "create-\(parentID)"
            }
        }
    }

    @State private var viewModel: TaskFormViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(LabelStore.self) private var labelStore
    @Environment(SessionStore.self) private var session
    @FocusState private var isTitleFocused: Bool
    @State private var dictation = DictationEngine.shared
    @State private var pendingAction: AgentOwnerActionKind?
    @State private var actionComment = ""
    @State private var replyingSubtask: ApiSubtask?
    @State private var subtaskReplyText = ""
    @State private var toast: TaskToastMessage?
    @State private var isAttachmentPickerPresented = false
    @State private var linkedTaskNavigation: LinkedTaskNavigation?
    @State private var isExistingTaskPickerPresented = false
    /// Какие шаги раскрыты. Своё состояние вместо `DisclosureGroup` — тот
    /// тянет за собой шеврон, от которого владелец отказался.
    @State private var expandedSubtaskIDs: Set<String> = []
    @State private var isAddingSubtask = false
    @State private var newSubtaskTitle = ""
    @State private var isDueEditorExpanded = false
    @State private var isEditorReady = false
    @State private var pendingSaveTask: Task<Void, Never>?

    /// Владелец 02.09.2026: длинные секции — под аккордеон, чтобы карточку
    /// можно было визуально сжать. По умолчанию развёрнуты.
    @State private var isNoteExpanded = true
    @State private var isSubtasksExpanded = true

    /// Показывает `QuickAddTaskView` как `.sheet` НАД этим экраном — временный
    /// мост, пока точка входа («+» → «Задача» в `RootShellView.swift`, App/,
    /// чужая папка) не переключена на прямой показ панели без пуша (диф —
    /// в отчёте оркестратору). Пока мост жив: перед панелью на мгновение
    /// виден пустой фон вместо экрана-источника — известный, не финальный вид.
    @State private var showQuickAdd: Bool
    /// «Развернуть» из панели — та же вью-модель (не копия: в
    /// `TaskAttachmentsController` уже могут лежать выбранные локальные
    /// файлы, копия их потеряла бы), эта же структура показывает `fullFormBody`.
    @State private var isExpanded: Bool

    /// `presetDueToday`/`startDictation` — контракт `INTEGRATION.md`,
    /// обновлён оркестратором по ходу этой задачи (`/task/new?due=today`,
    /// `/task/new?dictate=1` из `CreateMenu` веба): поле названия
    /// сфокусировано, кнопка микрофона показана. Само распознавание при
    /// тапе — `DictationEngine.shared` (просьба владельца 03.09.2026).
    init(taskID: String? = nil, presetDueToday: Bool = false, startDictation: Bool = false) {
        self.taskID = taskID
        self._viewModel = State(initialValue: TaskFormViewModel(taskID: taskID, presetDueToday: presetDueToday, startDictation: startDictation))
        self._showQuickAdd = State(initialValue: taskID == nil)
        self._isExpanded = State(initialValue: false)
    }

    /// «Развернуть» из `QuickAddTaskView` — тот же экран, СРАЗУ с готовой
    /// вью-моделью и в режиме полной формы (сохранение всё ещё «создание»:
    /// Вью-модель остаётся той же, поэтому введённые в панели данные
    /// не теряются.
    init(expandingFrom viewModel: TaskFormViewModel) {
        self.taskID = nil
        self._viewModel = State(initialValue: viewModel)
        self._showQuickAdd = State(initialValue: false)
        self._isExpanded = State(initialValue: true)
    }

    /// Создание полноценной дочерней задачи. В отличие от обычного «+»,
    /// сразу открываем полную форму: контекст родителя должен быть виден до
    /// сохранения, иначе связь создаётся незаметно для пользователя.
    init(linkedTo parentID: String, parentTitle: String, projectID: String?) {
        self.taskID = nil
        self._viewModel = State(initialValue: TaskFormViewModel(
            taskID: nil,
            parentTaskID: parentID,
            parentTaskTitle: parentTitle,
            presetProjectID: projectID
        ))
        self._showQuickAdd = State(initialValue: false)
        self._isExpanded = State(initialValue: true)
    }

    var body: some View {
        if viewModel.isEditing || isExpanded {
            fullFormBody
        } else {
            // Создание, панель ещё не показана/уже закрыта — фон-заглушка
            // моста (см. комментарий у `showQuickAdd`).
            Color.tfBackground
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .fullScreenCover(isPresented: $showQuickAdd, onDismiss: {
                    // `isExpanded` к этому моменту уже true, если сюда пришли
                    // через «развернуть» (устанавливается синхронно ДО сброса
                    // showQuickAdd в onExpand ниже) — тогда экран не закрываем,
                    // а показываем `fullFormBody`. Иначе (сохранили или смахнули
                    // панель вниз) — обычное закрытие экрана создания.
                    if !isExpanded { dismiss() }
                }) {
                    QuickAddTaskView(
                        viewModel: viewModel,
                        onSaved: { showQuickAdd = false },
                        onExpand: {
                            isExpanded = true
                            showQuickAdd = false
                        }
                    )
                    // Владелец 07.09.2026: «как в Todoist — не всплывающее
                    // окно, а надстройка прямо над клавиатурой». `.sheet` с
                    // детентами тут не годится: с фокусом в поле система
                    // резервирует место под клавиатуру и перескакивает на
                    // больший детент — панель раздувалась почти на весь экран.
                    // Поэтому прозрачный `fullScreenCover`: панель сама сидит
                    // у нижней кромки и поднимается вместе с клавиатурой
                    // штатным keyboard avoidance, фон мутит `QuickAddTaskView`.
                    .presentationBackground(.clear)
                }
        }
    }

    private var fullFormBody: some View {
        formNavigationBody
            .task { await loadScreen() }
            .onChange(of: isTitleFocused) { wasFocused, isFocused in
                if wasFocused, !isFocused { scheduleSave() }
            }
            .onChange(of: viewModel.title) { _, _ in scheduleSave() }
            .onChange(of: viewModel.taskDescription) { _, _ in scheduleSave() }
            .onChange(of: viewModel.dueDate) { _, _ in scheduleSave() }
            .onChange(of: viewModel.startMinutes) { _, _ in scheduleSave() }
            .onChange(of: viewModel.durationMin) { _, _ in scheduleSave() }
            .onChange(of: viewModel.projectId) { _, _ in scheduleSave() }
            .onChange(of: viewModel.priority) { _, _ in scheduleSave() }
            .onChange(of: viewModel.selectedLabelIds) { _, _ in scheduleSave() }
            .onChange(of: viewModel.assigneeId) { _, _ in scheduleSave() }
            .onDisappear(perform: handleDisappear)
    }

    private var formNavigationBody: some View {
        formPresentationBody
            .navigationDestination(item: $linkedTaskNavigation) { destination in
                switch destination {
                case .detail(let id):
                    TaskFormScreen(taskID: id)
                case .create(let parentID, let parentTitle, let projectID):
                    TaskFormScreen(linkedTo: parentID, parentTitle: parentTitle, projectID: projectID)
                }
            }
            .sheet(isPresented: $isExistingTaskPickerPresented) {
                LinkedTaskPicker(
                    tasks: taskStore.tasks,
                    excludedIDs: linkedTaskExcludedIDs,
                    onSelect: { task in await viewModel.linkExistingTask(task) }
                )
            }
            .onChange(of: linkedTaskNavigation) { previous, current in
                if previous != nil, current == nil { Task { await viewModel.loadIfNeeded() } }
            }
    }

    private var formPresentationBody: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingTask {
                TFLoading(.block)
                Spacer()
            } else if viewModel.notFound {
                Spacer()
                TFEmptyState(text: "Задача не найдена")
                Spacer()
            } else if viewModel.isEditing {
                nativeTaskDetail
            } else {
                ScrollView {
                    content
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.lg)
                        .padding(.bottom, TFSpacing.xl * 2)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Color.tfBackground)
        .overlay(alignment: .bottomTrailing) { if isTitleFocused { micKeyboardBar } }
        // AUD-001: свой header (× слева, «Готово»/«Сохранение…» справа) был
        // ВТОРЫМ рядом с системным навбаром — тут не просто дубль текста,
        // а форма с семантикой отмены/сохранения, обычный «‹ Назад» её не
        // заменяет. Штатный путь — `navigationBarBackButtonHidden` + свой
        // toolbar вместо самодельной шапки.
        .tfNativeHeader(viewModel.isEditing ? "Задача" : (viewModel.title.isEmpty ? "Новая задача" : viewModel.title), displayMode: .inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        // Отложенное сохранение перебиваем здесь, а не внутри
                        // `saveExistingEdits` — см. комментарий у метода.
                        pendingSaveTask?.cancel()
                        if viewModel.isEditing { await saveExistingEdits() }
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
            }
            if viewModel.isEditing {
                editingToolbarItems
            } else {
                if viewModel.showAiButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        aiStructureButton
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(viewModel.isSaving ? "Сохранение…" : "Готово")
                            .fontWeight(.semibold)
                    }
                    .tint(Color.tfRed)
                    .disabled(!viewModel.isSaveEnabled)
                }
            }
        }
        .alert("Комментарий", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        ), presenting: pendingAction) { action in
            TextField(action.commentRequired ? "Комментарий (обязателен)" : "Комментарий (необязательно)", text: $actionComment)
            Button("Отправить") {
                Task { await viewModel.performOwnerAction(action, comment: actionComment.isEmpty ? nil : actionComment, taskStore: taskStore) }
                actionComment = ""
                pendingAction = nil
            }
            .disabled(action.commentRequired && actionComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) {
                actionComment = ""
                pendingAction = nil
            }
        }
        .alert("Ответ агенту", isPresented: Binding(
            get: { replyingSubtask != nil },
            set: { if !$0 { replyingSubtask = nil } }
        ), presenting: replyingSubtask) { subtask in
            TextField("Комментарий", text: $subtaskReplyText)
            Button("Отправить") {
                Task { await viewModel.replyToSubtask(subtask, text: subtaskReplyText) }
                subtaskReplyText = ""
                replyingSubtask = nil
            }
            .disabled(subtaskReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) {
                subtaskReplyText = ""
                replyingSubtask = nil
            }
        }
        .alert("Новая подзадача", isPresented: $isAddingSubtask) {
            TextField("Название", text: $newSubtaskTitle)
            Button("Добавить") {
                let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await viewModel.addSubtask(title) }
                newSubtaskTitle = ""
            }
            .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) { newSubtaskTitle = "" }
        }
        .taskToast($toast)
        .fileImporter(
            isPresented: $isAttachmentPickerPresented,
            allowedContentTypes: [.item],
            onCompletion: handleAttachmentImport
        )
    }

    /// Единая карточка существующей задачи: это одновременно и просмотр,
    /// и форма. Никакого второго экрана за «Изменить» больше нет: название,
    /// описание и все свойства задачи активны прямо здесь.
    private var nativeTaskDetail: some View {
        List {
            if let message = viewModel.saveErrorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                // LOCK-117. Короткий номер карточки — тот самый, которым агенты
                // ссылаются на задачи в чате («карточка bb728617»). Владелец
                // 11.09.2026: «я-то их не вижу, поэтому понятия не имею, о какой
                // карточке ты говоришь». Намеренно неброско — .caption2 +
                // .tertiary, сноска, которую можно не читать.
                if let taskID = viewModel.taskID {
                    Text(taskID.prefix(8))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                TextField("Название задачи", text: $viewModel.title, axis: .vertical)
                    .font(.headline)
                    .lineLimit(1...6)
                    .focused($isTitleFocused)
                TextField("Описание", text: $viewModel.taskDescription, axis: .vertical)
                    .lineLimit(1...)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.tfBackground)

            Section("Подзадачи") {
                ForEach(viewModel.subtasks) { subtask in
                    nativeSubtaskRow(subtask)
                }
                Button {
                    newSubtaskTitle = ""
                    isAddingSubtask = true
                } label: {
                    Label("Добавить подзадачу", systemImage: "plus")
                }
            }
            .listRowBackground(Color.tfBackground)

            linkedTasksSection

            Section("Сведения") {
                Button {
                    isDueEditorExpanded.toggle()
                } label: {
                    LabeledContent("Срок", value: nativeDueText)
                }
                .buttonStyle(.plain)

                if isDueEditorExpanded {
                    ExistingTaskDueEditor(
                        dueDate: $viewModel.dueDate,
                        startMinutes: $viewModel.startMinutes,
                        durationMin: $viewModel.durationMin
                    )
                }

                Menu {
                    Button("Без проекта") { viewModel.projectId = nil }
                    ForEach(projectStore.projects) { project in
                        Button {
                            viewModel.projectId = project.id
                        } label: {
                            if viewModel.projectId == project.id {
                                Label(project.name, systemImage: "checkmark")
                            } else {
                                Text(project.name)
                            }
                        }
                    }
                } label: {
                    LabeledContent("Проект", value: projectStore.projects.first { $0.id == viewModel.projectId }?.name ?? "Не выбран")
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                        Button {
                            viewModel.priority = priority
                        } label: {
                            if viewModel.priority == priority {
                                Label(priority.label, systemImage: "checkmark")
                            } else {
                                Text(priority.label)
                            }
                        }
                    }
                } label: {
                    LabeledContent("Приоритет", value: viewModel.priority.label)
                }
                .buttonStyle(.plain)

                Menu {
                    if labelStore.labels.isEmpty {
                        Text("Нет доступных меток")
                    } else {
                        ForEach(labelStore.labels) { label in
                            Button {
                                let binding = labelBinding(label.id)
                                binding.wrappedValue.toggle()
                            } label: {
                                if viewModel.selectedLabelIds.contains(label.id) {
                                    Label(label.name, systemImage: "checkmark")
                                } else {
                                    Text(label.name)
                                }
                            }
                        }
                    }
                } label: {
                    LabeledContent("Метки", value: nativeLabelsText)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Не назначен") { viewModel.assigneeId = nil }
                    ForEach(viewModel.agents.filter { $0.type == .ai }) { agent in
                        Button {
                            viewModel.assigneeId = agent.id
                        } label: {
                            if viewModel.assigneeId == agent.id {
                                Label(agent.name, systemImage: "checkmark")
                            } else {
                                Text(agent.name)
                            }
                        }
                    }
                } label: {
                    LabeledContent("Исполнитель", value: viewModel.agents.first { $0.id == viewModel.assigneeId }?.name ?? "Не назначен")
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.tfBackground)

            if !viewModel.attachments.uploaded.isEmpty || !viewModel.attachments.pending.isEmpty {
                Section("Вложения") {
                    ForEach(viewModel.attachments.uploaded) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                    }
                    ForEach(viewModel.attachments.pending) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                    }
                }
            }

            // Владелец 07.09.2026: «комментарий не в самый низ, а в самый
            // верх — если это долгая задача, мне что, километр листать» —
            // поле ввода ПЕРЕД лентой (как было в старой `TaskJournalView`),
            // новые записи сверху (`TaskJournalEntry.merged` уже сортирует
            // «новые сверху»), скроллить до низа не нужно.
            Section("Комментарии") {
                HStack {
                    TextField("Комментарий", text: $viewModel.commentText)
                    Button("Отправить") { Task { await viewModel.sendComment() } }
                        .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(viewModel.journalEntries) { entry in
                    nativeJournalRow(entry)
                }
            }
            .listRowBackground(Color.tfBackground)
        }
        // Владелец 07.09.2026: «размести все элементы плоско, без лишних
        // подложек» — `Form` не всегда честно слушается `.listStyle(.plain)`
        // (осталась подложка-карточка под секциями даже после смены стиля),
        // `List` его уважает по-настоящему.
        .listStyle(.plain)
        // Карточка получалась полосатой: промежутки и заголовки секций шли на
        // нашем фоне, а сами строки — на системном чёрном, и это било в глаза
        // (владелец 09.09.2026: «текст задачи, текст описания — чёрный, он
        // должен быть везде одинаковым»). Гасим и подложку списка, и подложку
        // строк, оставляя один фон на весь экран.
        .listRowBackground(Color.tfBackground)
        .scrollContentBackground(.hidden)
        .background(Color.tfBackground)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await viewModel.refresh() }
    }

    private var linkedTasksSection: some View {
        Section {
            if let parent = viewModel.parentTask {
                linkedTaskRow(parent, relation: "Родительская")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            Task { await viewModel.unlinkFromParent() }
                        } label: {
                            Label("Отвязать", systemImage: "link.badge.minus")
                        }
                    }
            }

            ForEach(viewModel.childTasks) { child in
                linkedTaskRow(child, relation: "Дочерняя")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            Task { await viewModel.unlinkChildTask(child) }
                        } label: {
                            Label("Отвязать", systemImage: "link.badge.minus")
                        }
                    }
            }

            if viewModel.parentTask == nil, viewModel.childTasks.isEmpty {
                Text("Связанных задач пока нет")
                    .foregroundStyle(.secondary)
            }

            if let taskID {
                Button {
                    linkedTaskNavigation = .create(
                        parentID: taskID,
                        parentTitle: viewModel.title,
                        projectID: viewModel.projectId
                    )
                } label: {
                    Label("Создать связанную задачу", systemImage: "plus")
                }

                Button {
                    isExistingTaskPickerPresented = true
                } label: {
                    Label("Связать существующую", systemImage: "link.badge.plus")
                }
            }
        } header: {
            Text("Связанные задачи")
        } footer: {
            Text("Это полноценные дочерние задачи со своими сроками, исполнителями и статусами. Чек-лист «Подзадачи» остаётся отдельным.")
        }
        .listRowBackground(Color.tfBackground)
    }

    private func linkedTaskRow(_ task: ApiTask, relation: String) -> some View {
        let status = linkedTaskStatus(task)
        return Button {
            linkedTaskNavigation = .detail(task.id)
        } label: {
            HStack(spacing: TFSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Label("\(relation) · \(status.text)", systemImage: status.icon)
                        .font(.caption)
                        .foregroundStyle(status.color)
                }
                Spacer(minLength: TFSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Открывает связанную задачу")
    }

    private func linkedTaskStatus(_ task: ApiTask) -> (icon: String, text: String, color: Color) {
        if task.status == .completed {
            return ("checkmark.circle.fill", "Выполнена", .green)
        }
        switch task.agentState {
        case .review:
            return ("eye.fill", "На ревью", .blue)
        case .blocked:
            return ("exclamationmark.triangle.fill", "Заблокирована", .orange)
        case .inProgress:
            return ("play.circle.fill", "В работе", .secondary)
        case nil:
            return ("circle", "Открыта", .secondary)
        }
    }

    private var linkedTaskExcludedIDs: Set<String> {
        var ids = viewModel.ancestorTaskIDs
        ids.formUnion(viewModel.childTasks.map(\.id))
        if let taskID { ids.insert(taskID) }
        return ids
    }

    /// Шаг: строка, а под ней — то, что к ней относится.
    ///
    /// Владелец 09.09.2026: живая работа агента должна читаться на самом шаге,
    /// а не отдельной плашкой сверху. «Понаставят агента сразу пять в
    /// активностях — а так я реально вижу, по какой он работает». Поэтому:
    /// у идущего шага вместо пустого кружка крутится кольцо, тап по названию
    /// раскрывает под ним, что агент делает прямо сейчас; шаг закрыт — тот же
    /// тап показывает оставленный итог. Ничего не меняется в привычке: щёлкнул
    /// и смотришь, просто содержимое зависит от состояния шага.
    ///
    /// `DisclosureGroup` не используем — он рисует шеврон, а владелец их
    /// не хочет («функционал оставить, эффект тот же»). Раскрытие своё, по
    /// тапу на название; кружок остаётся отдельной кнопкой «сделано», иначе
    /// один жест значил бы две разные вещи.
    @ViewBuilder
    private func nativeSubtaskRow(_ subtask: ApiSubtask) -> some View {
        let isRunning = subtask.state == .running
        let hasDetails = subtask.result?.isEmpty == false
            || subtask.agentState == .blocked
            || subtask.agentState == .review
            || (isRunning && viewModel.activity.isActive)
        let isOpen = expandedSubtaskIDs.contains(subtask.id)

        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(spacing: TFSpacing.md) {
                Button {
                    guard subtask.agentState != .review else { return }
                    Task { await viewModel.toggleSubtaskDone(subtask) }
                } label: {
                    subtaskMark(subtask, isRunning: isRunning)
                }
                .buttonStyle(.plain)
                .disabled(subtask.agentState == .review)

                Text(subtask.title)
                    .strikethrough(subtask.done)
                    .foregroundStyle(subtask.done ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasDetails else { return }
                withAnimation(.easeInOut(duration: TFDuration.fast)) {
                    if isOpen { expandedSubtaskIDs.remove(subtask.id) }
                    else { expandedSubtaskIDs.insert(subtask.id) }
                }
            }

            if isOpen {
                subtaskDetails(subtask, isRunning: isRunning)
                    .padding(.leading, 21 + TFSpacing.md)
            }
        }
    }

    /// Отметка слева: крутится, пока шаг идёт.
    @ViewBuilder
    private func subtaskMark(_ subtask: ApiSubtask, isRunning: Bool) -> some View {
        if isRunning {
            TFSubtaskStatusRing(.running)
        } else {
            Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(subtask.done ? Color.tfTeal : .secondary)
                .frame(width: 21, height: 21)
        }
    }

    /// Что показываем под раскрытым шагом: у идущего — чем агент занят, у
    /// закрытого или заблокированного — его итог и кнопки владельца.
    @ViewBuilder
    private func subtaskDetails(_ subtask: ApiSubtask, isRunning: Bool) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if isRunning, viewModel.activity.isActive {
                if let text = viewModel.activity.text {
                    Text(text)
                        .foregroundStyle(.primary)
                }
                ForEach(viewModel.activity.actions.suffix(5).reversed()) { action in
                    HStack(alignment: .top, spacing: TFSpacing.sm) {
                        Circle()
                            .fill(Color.tfDim)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(action.text ?? action.target)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                    }
                }
            }
            if let result = subtask.result, !result.isEmpty {
                Text(result).foregroundStyle(.secondary)
            }
            if isOwner, subtask.agentState == .review {
                Button("Принять") { Task { await viewModel.acceptSubtask(subtask) } }
                Button("Вернуть на доработку") { replyingSubtask = subtask }
            } else if isOwner, subtask.agentState == .blocked {
                Button("Ответить") { replyingSubtask = subtask }
            }
        }
    }

    /// Плоская строка ленты — без аватарок/цветных плашек `TaskJournalView`
    /// (та осталась только в мёртвом `TaskDetailScreen`), обычный `Text` в
    /// `Form`, текст события — тот же словарь §19.2 (`TaskJournalView.eventText`).
    @ViewBuilder
    private func nativeJournalRow(_ entry: TaskJournalEntry) -> some View {
        switch entry {
        case .comment(let comment):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(comment.userName?.isEmpty == false ? comment.userName! : "Система")
                        .font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    if let date = comment.createdAtDate {
                        Text(TaskDateText.relativeTime(date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(comment.text)
            }
        case .event(let event):
            HStack {
                Text(TaskJournalView.eventText(event)).foregroundStyle(.secondary)
                Spacer()
                if let date = event.createdAtDate {
                    Text(TaskDateText.relativeTime(date)).foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
    }

    private var nativeDueText: String {
        guard let dueDate = viewModel.dueDate else { return "Не установлен" }
        let date = TaskDateText.dueLabel(dueDate)
        guard let minutes = viewModel.startMinutes else { return date }
        return "\(date), \(String(format: "%02d:%02d", minutes / 60, minutes % 60))"
    }

    private func labelBinding(_ labelID: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedLabelIds.contains(labelID) },
            set: { selected in
                if selected {
                    viewModel.selectedLabelIds.insert(labelID)
                } else {
                    viewModel.selectedLabelIds.remove(labelID)
                }
            }
        )
    }

    private var nativeLabelsText: String {
        let labels = labelStore.labels.filter { viewModel.selectedLabelIds.contains($0.id) }.map(\.name)
        return labels.isEmpty ? "Не выбраны" : labels.joined(separator: ", ")
    }

    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// Единственная кнопка справа — системное меню, как в эталонной
    /// карточке. Отдельной кнопки «Изменить» и галочки сохранения нет:
    /// поля активны сразу и сохраняются автоматически.
    @ToolbarContentBuilder
    private var editingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if viewModel.showAiButton {
                    Button {
                        // Стаб — см. `aiStructureButton`.
                    } label: {
                        Label("Структурировать с AI", systemImage: "sparkles")
                    }
                }
                if isOwner, let state = viewModel.agentState {
                    ownerActionMenuItems(state)
                }
                if isOwner {
                    // Готовность к самозахвату (миграция 026, карточка
                    // 04426aeb). Кнопка одна и в том же меню «…», где уже
                    // живут действия владельца — отдельной иконкой в
                    // topBarTrailing конкурировать за место не даём. Сервер
                    // примет PATCH только от владельца; кнопка скрыта от
                    // остальных условием `isOwner` сверху.
                    Button {
                        Task { await viewModel.toggleReadyFlag(taskStore: taskStore) }
                    } label: {
                        Label(
                            viewModel.readyForPickup
                                ? "Снять флаг готовности"
                                : "Готово к работе",
                            systemImage: viewModel.readyForPickup
                                ? "flag.slash"
                                : "flag.fill"
                        )
                    }
                }
                Button { isAttachmentPickerPresented = true } label: {
                    Label("Прикрепить файл", systemImage: "paperclip")
                }
                Button { outputDynamicIsland() } label: {
                    Label("Вывести в Dynamic Island", systemImage: "bolt.badge.a")
                }
                Button { saveAsTemplate() } label: {
                    Label("Сохранить как шаблон", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.tfText)
            }
        }
    }

    /// Перенесено буквально из `TaskDetailScreen.ownerActionMenuItems` —
    /// та же логика (§19.2 AgentOwnerActions), другой источник состояния.
    @ViewBuilder
    private func ownerActionMenuItems(_ state: AgentState) -> some View {
        switch state {
        case .review:
            Button { Task { await viewModel.performOwnerAction(.acceptReview, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять", systemImage: "checkmark")
            }
            Button { pendingAction = .returnToWorkFromReview } label: {
                Label("Вернуть на доработку", systemImage: "arrow.uturn.backward")
            }
        case .blocked:
            Button { pendingAction = .replyAndReturnFromBlocked } label: {
                Label("Ответить и вернуть в работу", systemImage: "arrowshape.turn.up.left")
            }
            Button { Task { await viewModel.performOwnerAction(.acceptAndClose, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
        case .inProgress:
            Button { Task { await viewModel.performOwnerAction(.returnToWorkFromInProgress, comment: nil, taskStore: taskStore) } } label: {
                Label("Вернуть на доработку", systemImage: "arrow.uturn.backward")
            }
            Button { Task { await viewModel.performOwnerAction(.acceptAndClose, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
        }
    }

    private func outputDynamicIsland() {
        // Тост здесь больше не «по спеке»: он сообщает то, что реально
        // произошло. Саму активность поднимает вьюмодель — у неё и задача,
        // и клиент API (10.09.2026, карточка cd831b02).
        guard #available(iOS 16.2, *) else {
            toast = TaskToastMessage("Островок доступен с iOS 16.2")
            return
        }
        Task {
            toast = TaskToastMessage(await viewModel.outputToDynamicIsland())
        }
    }

    private func saveAsTemplate() {
        // Перенесено из `TaskDetailScreen` буквально — на сервере нет
        // эндпоинта шаблонов, тост показывается по спеке.
        toast = TaskToastMessage("Задача сохранена в шаблоны")
    }

    /// `MicKeyboardBar` — spec/SCREENS-2.md §0.7: плавающая круглая кнопка
    /// 44×44 над клавиатурой, полупрозрачное стекло. Тап — старт записи,
    /// повторный тап — стоп + распознавание (`DictationEngine`, просьба
    /// владельца 03.09.2026 «подключи распознавание речи»). Текст дописывается
    /// в название через пробел, а не заменяет — так же, как обычная печать.
    private var micKeyboardBar: some View {
        Button {
            Task { await toggleDictation() }
        } label: {
            Group {
                switch dictation.recordingState {
                case .recording:
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: true)
                case .transcribing:
                    ProgressView().tint(Color.tfText)
                default:
                    Image(systemName: "mic.fill")
                }
            }
            .font(.system(size: 18))
            .foregroundStyle(dictation.recordingState == .recording ? Color.tfRed : Color.tfText)
            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(TFTapScaleStyle())
        .disabled(dictation.recordingState == .transcribing)
        .padding(.trailing, TFSpacing.lg)
        .padding(.bottom, TFSpacing.lg)
    }

    private func toggleDictation() async {
        switch dictation.recordingState {
        case .idle, .failed:
            await dictation.startRecording()
        case .recording:
            guard let text = await dictation.stopRecordingAndTranscribe() else { return }
            if viewModel.title.isEmpty {
                viewModel.title = text
            } else {
                viewModel.title += (viewModel.title.hasSuffix(" ") ? "" : " ") + text
            }
        case .transcribing:
            break
        }
    }

    // MARK: - Тело

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xl) {
            // 02.09.2026: статичная подпись «Изменить задачу»/«Новая задача»
            // убрана — дублировала то, что уже видно в шапке (см.
            // `tfNativeHeader`); жирным вместо неё теперь само название,
            // см. `titleField`. Кнопка «Структурировать с AI» переехала в
            // шапку (toolbar), здесь больше не рисуется.
            // 02.09.2026, фикс после совета: `.disabled(isReadOnly)` раньше
            // висел на ВСЁМ `content` — вместе с полями он глушил и кнопку
            // заголовка аккордеона (Заметка/Подзадачи не сворачивались), и
            // кнопки внутри `SubtaskFeedView` (кольца, Принять/Ответить).
            // Теперь точечно — только на реальных полях ввода.
            if let parentTitle = viewModel.parentTitle {
                Label("Связанная задача для «\(parentTitle)»", systemImage: "arrow.turn.down.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            titleField
            noteSection
            subtasksSection
            // 02.09.2026, владелец: «зачем эта здоровая хрень, когда файлов
            // нет» — строка показывается только если есть что показать;
            // добавление файла теперь пункт «…» (`isAttachmentPickerPresented`).
            if !viewModel.attachments.uploaded.isEmpty || !viewModel.attachments.pending.isEmpty {
                AttachmentsFieldView(controller: viewModel.attachments, showAddButton: false)
            }

            TFFieldGroup {
                DueDateFieldView(dueDate: $viewModel.dueDate, startMinutes: $viewModel.startMinutes, durationMin: $viewModel.durationMin)
                TFFieldDivider()
                ProjectFieldView(projects: projectStore.projects, selectedProjectId: $viewModel.projectId)
                TFFieldDivider()
                PriorityFieldView(priority: $viewModel.priority)
                TFFieldDivider()
                LabelsFieldView(allLabels: labelStore.labels, selectedIds: $viewModel.selectedLabelIds)
            }

            AssigneeFieldView(agents: viewModel.agents, selectedAgentId: $viewModel.assigneeId)

            TFErrorBanner(viewModel.directoriesErrorMessage, variant: .block)
            TFErrorBanner(viewModel.saveErrorMessage, variant: .block)
        }
    }

    private var aiStructureButton: some View {
        Button {
            // Стаб: `/ai/structure-task` есть на сервере (spec/API.md §5.11),
            // но точная форма ответа не проверена живым запросом в этой
            // задаче — рисковать угадыванием decode-схемы не стал (см. отчёт).
        } label: {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                Text("Структурировать с AI").tfText(.body).fontWeight(.semibold)
            }
            // Была фиолетово-розовая заливка градиентом — просьба владельца
            // 03.09.2026: причесать под лаконичный стиль «Моделей и голосов»
            // (без цветных плашек), тот же нейтральный `tfCard2`, что у
            // «Сегодня»/«Завтра» в `DueDateFieldView`.
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, TFSpacing.lg)
            .padding(.vertical, TFSpacing.sm)
            .background(Color.tfCard2)
            .clipShape(Capsule())
        }
        .buttonStyle(TFTapScaleStyle())
    }

    private var titleField: some View {
        TextField("", text: $viewModel.title, prompt: Text("Название задачи").foregroundStyle(Color.tfDim), axis: .vertical)
            .tfText(.taskTitle)
            .foregroundStyle(Color.tfText)
            .lineLimit(1...6)
            .focused($isTitleFocused)
    }

    /// 02.09.2026, уточнение владельца: шеврон (аккордеон) — вернуть,
    /// убирать его не просили. Жаловался на другое — поле с `lineLimit`
    /// заводило СВОЙ внутренний скролл («отдельное окошко, которое
    /// листается») при длинном тексте в правке. Верхнюю границу убрал —
    /// поле растёт вместе со страницей, второго скролла внутри нет.
    private var noteSection: some View {
        TFCollapsibleSection(title: "Заметка", isExpanded: $isNoteExpanded) {
            TextField("", text: $viewModel.taskDescription, prompt: Text("Описание").foregroundStyle(Color.tfDim), axis: .vertical)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .lineLimit(1...)
        }
    }

    /// Чек-лист для развёрнутой формы создания. Существующая задача использует
    /// плоскую секцию `nativeTaskDetail` с отдельной кнопкой добавления.
    private var subtasksSection: some View {
        TFCollapsibleSection(title: "Подзадачи", isExpanded: $isSubtasksExpanded) {
            SubtaskDraftListView(drafts: $viewModel.subtaskDrafts)
        }
    }

    private func scheduleSave() {
        guard viewModel.isEditing, isEditorReady else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await saveExistingEdits()
        }
    }

    /// ⚠️ Здесь НЕЛЬЗЯ трогать `pendingSaveTask`: этот метод вызывается в том
    /// числе изнутри самой `pendingSaveTask` (см. `scheduleSave`), и отмена
    /// отменяла задачу, внутри которой выполнялась. `URLSession` дальше
    /// создавался в уже отменённом контексте и бросал `URLError.cancelled` —
    /// владелец видел «Сеть недоступна: cancelled» на любой правке карточки
    /// (09.09.2026, ловилось на «Срок» → «Убрать дату и время»). Отменяет
    /// отложенное сохранение тот, кто его перебивает: `scheduleSave` и
    /// `handleDisappear`.
    private func saveExistingEdits() async {
        guard viewModel.isEditing, isEditorReady else { return }
        _ = await viewModel.save(taskStore: taskStore)
    }

    private func handleDisappear() {
        viewModel.stopPolling()
        pendingSaveTask?.cancel()
        guard viewModel.isEditing, isEditorReady else { return }
        Task { await saveExistingEdits() }
    }

    private func handleAttachmentImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task { await viewModel.attachments.add(url: url) }
    }

    private func loadScreen() async {
        await viewModel.loadIfNeeded()
        await viewModel.loadAgents()
        if taskStore.tasks.isEmpty { await taskStore.load() }
        if projectStore.projects.isEmpty { await projectStore.load() }
        if labelStore.labels.isEmpty { await labelStore.load() }
        if viewModel.startDictation { isTitleFocused = true }
        await viewModel.loadActivity()
        viewModel.startPolling()
        isEditorReady = true
    }

    private func submit() async {
        if await viewModel.save(taskStore: taskStore) {
            dismiss()
        }
    }
}

/// Тот же редактор срока, что в форме создания: быстрые даты,
/// календарь, системный барабан времени и длительность.
private struct ExistingTaskDueEditor: View {
    @Binding var dueDate: Date?
    @Binding var startMinutes: Int?
    @Binding var durationMin: Int?

    private static let durationOptions: [(minutes: Int, label: String)] = [
        (15, "15м"), (30, "30м"), (45, "45м"), (60, "1ч"), (120, "2ч"), (180, "3ч"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            HStack(spacing: TFSpacing.sm) {
                quickButton("Сегодня") { dueDate = moscowStartOfDay(offsetDays: 0) }
                quickButton("Завтра") { dueDate = moscowStartOfDay(offsetDays: 1) }
            }

            // Владелец 09.09.2026: «барабан на полстраницы, как календарь».
            // Был самописный календарь-сетка плюс `.wheel` во всю высоту —
            // теперь системные компактные пикеры: в строке видно значение,
            // по тапу всплывает маленькая панелька, как в Напоминаниях.
            // Заодно ушёл перекос барабана влево — он брался от `.wheel`
            // с `labelsHidden` в колонке с выравниванием по левому краю.
            DatePicker("Дата", selection: dueDateBinding, displayedComponents: .date)
            DatePicker("Время", selection: startTimeBinding, displayedComponents: .hourAndMinute)

            if dueDate != nil {
                Picker("Продолжительность", selection: $durationMin) {
                    Text("Не указана").tag(Int?.none)
                    ForEach(Self.durationOptions, id: \.minutes) { option in
                        Text(option.label).tag(Optional(option.minutes))
                    }
                }

                Button {
                    dueDate = nil
                } label: {
                    Text(startMinutes != nil ? "Убрать дату и время" : "Убрать дату")
                        .tfText(.body)
                        .foregroundStyle(Color.tfCoral)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TFTapFadeStyle())
            }
        }
        .padding(.vertical, TFSpacing.sm)
        .onChange(of: dueDate == nil) { _, isNil in
            if isNil {
                startMinutes = nil
                durationMin = nil
            }
        }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .tfText(.body)
                .fontWeight(.medium)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity)
                .frame(height: TFHitTarget.min)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        }
        .buttonStyle(TFTapScaleStyle())
    }

    /// Компактному `DatePicker` нужна непустая дата: пока срока нет,
    /// показываем сегодня, а записываем только когда пользователь выбрал.
    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { dueDate ?? moscowStartOfDay(offsetDays: 0) ?? Date() },
            set: { dueDate = $0 }
        )
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = startMinutes ?? 9 * 60
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                startMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func durationButton(_ option: (minutes: Int, label: String)) -> some View {
        let isSelected = durationMin == option.minutes
        return Button {
            durationMin = isSelected ? nil : option.minutes
        } label: {
            Text(option.label)
                .tfText(.action)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : Color.tfText)
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, TFSpacing.sm)
                .background(isSelected ? Color.tfRed : Color.tfCard2)
                .clipShape(Capsule())
        }
        .buttonStyle(TFTapScaleStyle())
    }

    private func moscowStartOfDay(offsetDays: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TaskDateText.moscow
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offsetDays, to: today) ?? today
    }
}

/// Системная шторка выбора уже существующей корневой задачи. Показываем
/// только задачи без `parent_id`: это не даёт случайно выдернуть ребёнка из
/// другой ветки и отсекает основной источник циклических связей.
private struct LinkedTaskPicker: View {
    let tasks: [ApiTask]
    let excludedIDs: Set<String>
    let onSelect: (ApiTask) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var linkingID: String?
    @State private var errorMessage: String?

    private var candidates: [ApiTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks
            .filter { $0.parentId == nil && !excludedIDs.contains($0.id) }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted {
                if $0.status != $1.status { return $0.status == .active }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Нет доступных задач",
                        systemImage: "link",
                        description: Text("Создайте новую связанную задачу или измените строку поиска.")
                    )
                } else {
                    ForEach(candidates) { task in
                        Button {
                            guard linkingID == nil else { return }
                            linkingID = task.id
                            Task {
                                if await onSelect(task) {
                                    dismiss()
                                } else {
                                    linkingID = nil
                                    errorMessage = "Не удалось связать задачу"
                                }
                            }
                        } label: {
                            HStack(spacing: TFSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(task.status == .completed ? "Выполнена" : "Открыта")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: TFSpacing.sm)
                                if linkingID == task.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "link.badge.plus")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(linkingID != nil)
                        .accessibilityHint("Добавляет задачу как дочернюю")
                    }
                }
            }
            .navigationTitle("Связать задачу")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск задач")
            .alert("Ошибка", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

/// Сворачиваемая секция формы («Заметка», «Подзадачи» — 02.09.2026, владелец:
/// «всё, что длиннючее, — под аккордеон, чтобы карточку можно было сжать»).
/// Тот же принцип, что у `IntegrationAccordionCard` в Settings (заголовок +
/// шеврон, тап сворачивает), но без иконки/бейджа — здесь не нужны, а своя,
/// более простая структура ближе к остальным секциям формы (без обводки-карточки).
private struct TFCollapsibleSection<Content: View>: View {
    let title: String
    /// Счётчик вроде «5 из 11» — то, что раньше показывал `SubtaskFeedView`
    /// сам, отдельной строкой рядом с заголовком.
    var trailingBadge: String? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: TFDuration.fast)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title).tfText(.title).foregroundStyle(Color.tfText)
                    if let trailingBadge {
                        Text(trailingBadge).tfText(.action).foregroundStyle(Color.tfSub)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tfSub)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TFTapRowStyle())

            if isExpanded {
                content()
            }
        }
    }
}
