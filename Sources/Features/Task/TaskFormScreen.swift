import SwiftUI

/// Два режима задачи во всём приложении: компактная панель
/// `QuickAddTaskView` для создания и одна плоская системная шторка для
/// существующей задачи. Все поля в готовой задаче активны сразу.
struct TaskFormScreen: View {
    let taskID: String?

    private enum LinkedTaskNavigation: Identifiable, Hashable {
        case detail(String)

        var id: String {
            switch self {
            case .detail(let id): "detail-\(id)"
            }
        }
    }

    private enum DictationTarget: Equatable {
        case title, description, comment, subtask(String), newSubtask
    }

    @State private var viewModel: TaskFormViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(LabelStore.self) private var labelStore
    @Environment(SessionStore.self) private var session
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isDescriptionFocused: Bool
    @FocusState private var isCommentFocused: Bool
    @State private var dictation = DictationEngine.shared
    @State private var dictationTarget: DictationTarget = .title
    /// Фокус блока описания, живые метки форматирования и запрос ссылки —
    /// общее состояние блочного редактора (`BlockDocumentEditor`), такое же,
    /// как у заметки: лента над клавиатурой живёт вне дерева SwiftUI и
    /// обычный `@State` ей не виден.
    @State private var descriptionFocus = NoteEditorFocusState()
    @State private var pendingAction: AgentOwnerActionKind?
    @State private var actionComment = ""
    @State private var replyingSubtask: ApiSubtask?
    @State private var subtaskReplyText = ""
    @State private var toast: TaskToastMessage?
    @State private var isAttachmentPickerPresented = false
    /// Выбор документа из базы знаний (второй источник у «Прикрепить файл»).
    @State private var isKnowledgePickerPresented = false
    /// Вложение, которое ЗАМЕНЯЕМ (длинное нажатие → «Заменить…»): после
    /// загрузки нового старое удаляем.
    @State private var replaceAttachmentTarget: ApiAttachment?
    /// Открытый отчёт: показываем его документ-зеркало.
    @State private var openedReportNoteID: String?

    private enum AttachmentSource { case phone, knowledge }
    @State private var isDeleteConfirmationPresented = false
    @State private var linkedTaskNavigation: LinkedTaskNavigation?
    @State private var isExistingTaskPickerPresented = false
    @State private var linkedTaskQuickAddViewModel: TaskFormViewModel?
    @State private var expandedLinkedTaskViewModel: TaskFormViewModel?
    /// Тексты шагов, которые правят прямо сейчас (id шага → набранное).
    @State private var subtaskTitleDrafts: [String: String] = [:]
    @FocusState private var focusedSubtaskID: String?
    @State private var newSubtaskTitle = ""
    @FocusState private var isNewSubtaskFocused: Bool
    @State private var isDueEditorExpanded = false
    @State private var isEditorReady = false
    @State private var pendingSaveTask: Task<Void, Never>?

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
                if isFocused { dictationTarget = .title }
                if wasFocused, !isFocused { scheduleSave() }
            }
            .onChange(of: isDescriptionFocused) { _, isFocused in
                if isFocused { dictationTarget = .description }
            }
            .onChange(of: isCommentFocused) { _, isFocused in
                if isFocused { dictationTarget = .comment }
            }
            .onChange(of: isNewSubtaskFocused) { _, isFocused in
                if isFocused { dictationTarget = .newSubtask }
            }
            .onChange(of: viewModel.title) { _, _ in scheduleSave() }
            .onChange(of: viewModel.taskDescription) { _, _ in scheduleSave() }
            .onChange(of: viewModel.dueDate) { _, _ in scheduleSave() }
            .onChange(of: viewModel.startMinutes) { _, _ in scheduleSave() }
            .onChange(of: viewModel.durationMin) { _, _ in scheduleSave() }
            .onChange(of: viewModel.runRepeat) { _, _ in scheduleSave() }
            .onChange(of: viewModel.repeatUntil) { _, _ in scheduleSave() }
            .onChange(of: viewModel.projectId) { _, _ in scheduleSave() }
            .onChange(of: viewModel.priority) { _, _ in scheduleSave() }
            .onChange(of: viewModel.selectedLabelIds) { _, _ in scheduleSave() }
            .onChange(of: viewModel.ownerSelectedRole) { _, _ in scheduleSave() }
            .onChange(of: viewModel.assigneeId) { _, _ in scheduleSave() }
            .onDisappear(perform: handleDisappear)
    }

    private var formNavigationBody: some View {
        formPresentationBody
            .navigationDestination(item: $linkedTaskNavigation) { destination in
                switch destination {
                case .detail(let id):
                    TaskFormScreen(taskID: id)
                }
            }
            .sheet(isPresented: $isExistingTaskPickerPresented) {
                LinkedTaskPicker(
                    tasks: taskStore.tasks,
                    excludedIDs: linkedTaskExcludedIDs,
                    onSelect: { task in await viewModel.linkExistingTask(task) }
                )
            }
            .fullScreenCover(isPresented: linkedTaskQuickAddPresented, onDismiss: {
                Task { await viewModel.loadIfNeeded() }
            }) {
                if let linkedTaskQuickAddViewModel {
                    QuickAddTaskView(
                        viewModel: linkedTaskQuickAddViewModel,
                        onSaved: { self.linkedTaskQuickAddViewModel = nil },
                        onExpand: { expandLinkedTaskQuickAdd(linkedTaskQuickAddViewModel) }
                    )
                }
            }
            .fullScreenCover(isPresented: expandedLinkedTaskPresented, onDismiss: {
                Task { await viewModel.loadIfNeeded() }
            }) {
                if let expandedLinkedTaskViewModel {
                    TaskFormScreen(expandingFrom: expandedLinkedTaskViewModel)
                }
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
            } else {
                // Одна форма на всё: развёрнутое создание выглядит и ведёт
                // себя ровно как открытая задача. Владелец 11.09.2026 —
                // «расширенную форму заменить на нашу стандартную обычную».
                // Отдельной анкеты (`TFCollapsibleSection` + `TFFieldGroup`)
                // больше нет.
                nativeTaskDetail
            }
        }
        .background(Color.tfBackground)
        // AUD-001: свой header (× слева, «Готово»/«Сохранение…» справа) был
        // ВТОРЫМ рядом с системным навбаром — тут не просто дубль текста,
        // а форма с семантикой отмены/сохранения, обычный «‹ Назад» её не
        // заменяет. Штатный путь — `navigationBarBackButtonHidden` + свой
        // toolbar вместо самодельной шапки.
        .tfNativeHeader(viewModel.isEditing ? "Задача" : (viewModel.title.isEmpty ? "Новая задача" : viewModel.title), displayMode: .inline)
        // Мягкая кромка прокрутки под шапкой (iOS 26+).
        //
        // По умолчанию система гасит уезжающий контент жёстко: на кадре
        // 16.09.2026 текст обрывался ровно по горизонтальной линии — строка
        // «Кегли-сироты…» срезана посередине, выше линии буквы притушены,
        // ниже целые. Владелец: «градация прям чёткая, есть линия, не мутная».
        //
        // `.soft` растягивает затухание, и текст уходит под шапку размыто,
        // без видимой границы. Это штатный путь Apple вместо самодельных
        // градиентных подложек (ср. TFHeaderBackdrop, который делает то же
        // руками там, где шапка не нативная).
        //
        // Цель сборки — iOS 18, поэтому под проверкой доступности: на
        // старых системах эффекта нет вовсе и кромка остаётся прежней.
        .modifier(TFSoftTopScrollEdge())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                taskKeyboardDismissButton
                Spacer()
                taskKeyboardDictationButton
            }
            if viewModel.isEditing, let taskID = viewModel.taskID {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Задача").font(.headline)
                        Text(taskID.prefix(8)).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
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
                .accessibilityLabel("Закрыть")
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
        .confirmationDialog("Удалить задачу?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await deleteCurrentTask() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Задача будет удалена без возможности восстановления.")
        }
        .alert("Комментарий", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        ), presenting: pendingAction) { action in
            TextField(action.commentRequired ? "Комментарий (обязателен)" : "Комментарий (необязательно)", text: $actionComment)
            Button("Отправить") {
                // `Task` начинает выполняться после возврата из обработчика,
                // поэтому перед сбросом alert сохраняем снимок текста. Иначе
                // review → in_progress уходит без обязательного comment.
                let comment = TaskFormViewModel.ownerActionCommentForSubmission(actionComment)
                actionComment = ""
                pendingAction = nil
                Task { await viewModel.performOwnerAction(action, comment: comment, taskStore: taskStore) }
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
        .taskToast($toast)
        .fileImporter(
            isPresented: $isAttachmentPickerPresented,
            allowedContentTypes: [.item],
            onCompletion: handleAttachmentImport
        )
        .sheet(isPresented: $isKnowledgePickerPresented) {
            KnowledgePickerSheet { noteID, title in
                let old = replaceAttachmentTarget
                replaceAttachmentTarget = nil
                Task {
                    await attachKnowledgeNote(noteID: noteID, title: title)
                    if let old { await viewModel.attachments.removeUploaded(old) }
                }
            }
            .onDisappear { replaceAttachmentTarget = nil }
        }
        .sheet(isPresented: Binding(
            get: { openedReportNoteID != nil },
            set: { if !$0 { openedReportNoteID = nil } }
        )) {
            if let noteID = openedReportNoteID {
                NavigationStack { NoteEditorScreen(noteID: noteID) }
            }
        }
    }

    /// Длинное нажатие на вложение → «Заменить…»: запоминаем, что меняем, и
    /// открываем нужный источник. После успешной загрузки старое удаляется.
    private func replaceAttachment(from source: AttachmentSource, target: ApiAttachment) {
        replaceAttachmentTarget = target
        switch source {
        case .phone: isAttachmentPickerPresented = true
        case .knowledge: isKnowledgePickerPresented = true
        }
    }

    /// Единая карточка существующей задачи: это одновременно и просмотр,
    /// и форма. Никакого второго экрана за «Изменить» больше нет: название,
    /// описание и все свойства задачи активны прямо здесь.
    // 15.09.2026: список карточки развалился на секции-переменные.
    // Одним куском его тип вырастал настолько, что рантайм не мог
    // развернуть имя типа и падал переполнением стека на устройстве
    // (в симуляторе стек больше — там держалось). Вид и поведение
    // прежние, поделены только границы.
    @ViewBuilder private var headerSection: some View {
            Section {
                HStack(alignment: .center, spacing: TFSpacing.sm) {
                    TextField("Название задачи", text: $viewModel.title, axis: .vertical)
                        .font(.headline)
                        .lineLimit(1...6)
                        .focused($isTitleFocused)

                    if viewModel.readyForPickup {
                        TFReadyFlag()
                    }
                }
                .listRowSeparator(.hidden)

                if let ladder = viewModel.attemptLadder, ladder.currentStep > 0 {
                    HStack(spacing: TFSpacing.sm) {
                        if let state = viewModel.agentState {
                            Label(agentStateText(state), systemImage: agentStateIcon(state))
                                .tfText(.caption)
                                .foregroundStyle(agentStateColor(state))
                        }
                        AttemptLadderView(ladder: ladder, agentState: viewModel.agentState)
                    }
                    .accessibilityElement(children: .contain)
                    .listRowSeparator(.hidden)
                }

                // Тот же редактор, что в заметке: те же строки блоков, та же
                // лента над клавиатурой, тот же Enter/Backspace. Владелец
                // 13.09.2026 — «один единый формат с заметками».
                BlockDocumentEditor(
                    blocks: $viewModel.taskDescriptionBlocks,
                    focus: descriptionFocus,
                    placeholder: "Описание",
                    onEdit: { scheduleSave() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
    }

    @ViewBuilder private var detailsSection: some View {
            Section {
                Button {
                    isDueEditorExpanded.toggle()
                } label: {
                    LabeledContent("Срок", value: nativeDueText)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                .buttonStyle(.plain)

                if isDueEditorExpanded {
                    ExistingTaskDueEditor(
                        dueDate: $viewModel.dueDate,
                        startMinutes: $viewModel.startMinutes,
                        durationMin: $viewModel.durationMin,
                        runRepeat: $viewModel.runRepeat,
                        repeatUntil: $viewModel.repeatUntil
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
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
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
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
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
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                .buttonStyle(.plain)

                // Исполнитель — роль (AgentProfile), не учётка (LOCK-178).
                // «Автоматически» = роли нет, диспетчер подберёт её сам.
                Menu {
                    Button("Автоматически — оркестратор выберет агента") {
                        viewModel.ownerSelectedRole = nil
                        viewModel.assigneeId = nil
                    }
                    // Себя — тем же именем, что и в остальных местах: карточка
                    // на владельце. Назначенную на человека задачу агенты не
                    // берут и работник расписания не трогает; в истории видно
                    // имя, а не «кого-то».
                    if let me = session.currentUser {
                        Button {
                            viewModel.assigneeId = me.id
                            viewModel.ownerSelectedRole = nil
                        } label: {
                            if viewModel.assigneeId == me.id {
                                Label(me.name, systemImage: "checkmark")
                            } else {
                                Text(me.name)
                            }
                        }
                    }
                    ForEach(viewModel.roles) { role in
                        Button {
                            viewModel.ownerSelectedRole = role.role
                            viewModel.assigneeId = nil
                        } label: {
                            if viewModel.ownerSelectedRole == role.role {
                                Label(role.title, systemImage: "checkmark")
                            } else {
                                Text(role.title)
                            }
                        }
                    }
                } label: {
                    LabeledContent("Исполнитель", value: selectedRoleTitle)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                .buttonStyle(.plain)

                // Кто завёл карточку. Владелец 14.09.2026: «почему я не вижу
                // в карточке, кто создаёт карточки». Раньше это знал только
                // сервер. Строка не редактируется — создателя не меняют, и
                // она показывается лишь у сохранённых задач: у новой
                // создатель ещё не записан.
                if let creator = viewModel.creatorName, !creator.isEmpty {
                    LabeledContent("Создал", value: creator)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
            } header: {
                taskSectionHeader("Сведения")
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
    }

    // 15.09.2026: тип экрана стирается здесь намеренно. Цепочка
    // body → fullFormBody → formNavigationBody → formPresentationBody →
    // List копила такой generic-тип, что рантайм не мог развернуть его
    // имя и падал переполнением стека прямо при открытии карточки на
    // устройстве. AnyView разрывает цепочку: дальше вглубь тип не растёт.
    private var nativeTaskDetail: AnyView { AnyView(nativeTaskDetailBody) }

    private var nativeTaskDetailBody: some View {
        List {
            aiStructureStatusSection

            if let message = viewModel.saveErrorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .listRowSeparator(.hidden)
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }

            headerSection

            subtasksSection

            // У несохранённой задачи связывать нечего — секция появляется
            // вместе с самой задачей. Исключение — создание дочерней:
            // родитель уже известен и должен быть виден до сохранения.
            if viewModel.isEditing || viewModel.parentTitle != nil {
                linkedTasksSection
            }

            detailsSection

            if !viewModel.attachments.uploaded.isEmpty || !viewModel.attachments.pending.isEmpty {
                Section {
                    ForEach(viewModel.attachments.uploaded) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .contextMenu {
                                Button { replaceAttachment(from: .phone, target: attachment) } label: {
                                    Label("Заменить с iPhone", systemImage: "iphone")
                                }
                                Button { replaceAttachment(from: .knowledge, target: attachment) } label: {
                                    Label("Заменить из базы знаний", systemImage: "books.vertical")
                                }
                                Button(role: .destructive) {
                                    Task { await viewModel.attachments.removeUploaded(attachment) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await viewModel.attachments.removeUploaded(attachment) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                    ForEach(viewModel.attachments.pending) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .swipeActions {
                                Button(role: .destructive) {
                                    viewModel.attachments.removePending(attachment)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    taskSectionHeader("Вложения")
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }

            // Отчёты — «зеркало» документов из папки проекта: сам файл лежит
            // в документации, здесь название, автор и время; тап открывает
            // документ. Владелец 20.09.2026.
            if !viewModel.reports.isEmpty {
                Section {
                    ForEach(viewModel.reports) { report in
                        Button {
                            if let noteID = report.noteID { openedReportNoteID = noteID }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(report.title, systemImage: "doc.text")
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfText)
                                Text(reportSubtitle(report))
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfDim)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    taskSectionHeader("Отчёты")
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }

            // Владелец 07.09.2026: «комментарий не в самый низ, а в самый
            // верх — если это долгая задача, мне что, километр листать» —
            // поле ввода ПЕРЕД лентой (как было в старой `TaskJournalView`),
            // новые записи сверху (`TaskJournalEntry.merged` уже сортирует
            // «новые сверху»), скроллить до низа не нужно.
            // Ленты у несохранённой задачи нет: комментировать нечего.
            if viewModel.isEditing {
                Section {
                    HStack {
                        // Отправить можно и с клавиатуры, не целясь в
                        // «Отправить»: у поля в строке списка это главный
                        // способ (11.09.2026 — «хочу написать комментарий,
                        // не работает»). Кнопке нужен `.borderless`, иначе
                        // `List` отдаёт ей тап по всей строке, включая поле.
                        TextField("Комментарий", text: $viewModel.commentText, axis: .vertical)
                            .lineLimit(1...4)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .focused($isCommentFocused)
                            .submitLabel(.send)
                            .onSubmit { Task { await viewModel.sendComment() } }
                        Button("Отправить") { Task { await viewModel.sendComment() } }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ForEach(viewModel.journalEntries) { entry in
                        nativeJournalRow(entry)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    taskSectionHeader("Лента активности")
                }
                .listRowBackground(Color.tfBackground)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
        }
        // Владелец 07.09.2026: «размести все элементы плоско, без лишних
        // подложек» — `Form` не всегда честно слушается `.listStyle(.plain)`
        // (осталась подложка-карточка под секциями даже после смены стиля),
        // `List` его уважает по-настоящему.
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        // Карточка получалась полосатой: промежутки и заголовки секций шли на
        // нашем фоне, а сами строки — на системном чёрном, и это било в глаза
        // (владелец 09.09.2026: «текст задачи, текст описания — чёрный, он
        // должен быть везде одинаковым»). Гасим и подложку списка, и подложку
        // строк, оставляя один фон на весь экран.
        .listRowBackground(Color.tfBackground)
        .scrollContentBackground(.hidden)
        .background(Color.tfBackground)
        .scrollDismissesKeyboard(.interactively)
        // Ушли из строки шага — сохранили её название. Тот же принцип, что
        // у названия задачи выше: отдельной кнопки «сохранить» нет.
        .onChange(of: focusedSubtaskID) { previous, current in
            if let current { dictationTarget = .subtask(current) }
            guard let previous,
                  let subtask = viewModel.subtasks.first(where: { $0.id == previous })
            else { return }
            commitSubtaskTitle(subtask)
        }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
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
                Button {
                    startLinkedTaskQuickAdd()
                } label: {
                    Text("Добавить связанную задачу")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                }
                .listRowSeparator(.hidden)
            }

        } header: {
            taskSectionHeader("Связанные задачи")
        }
        .listRowBackground(Color.tfBackground)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)

        // Чаты, привязанные к задаче. Секция только ПЕРЕХОДИТ в переписку:
        // свой чат внутри карточки не заводится и не рисуется — для этого есть
        // отдельный экран (владелец 21.09.2026: «заводить прям чат прямо в
        // карточке не надо, надо чтобы просто переходил»). Появляется только
        // когда чат уже привязан — со стороны чата.
        if !viewModel.taskChats.isEmpty {
            Section {
                ForEach(viewModel.taskChats) { chat in
                    NavigationLink(value: AppRoute.roleChat(id: chat.id)) {
                        HStack(spacing: TFSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chat.displayTitle)
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfSub)
                                    .lineLimit(2)
                                if let members = chat.membersCount, members > 0 {
                                    Text("Участников: \(members)")
                                        .tfText(.meta)
                                        .foregroundStyle(Color.tfDim)
                                }
                            }
                            Spacer(minLength: TFSpacing.sm)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowSeparator(.hidden)
                }
            } header: {
                taskSectionHeader("Чат по задаче")
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
    }

    private func linkedTaskRow(_ task: ApiTask, relation: String) -> some View {
        let status = linkedTaskStatus(task)
        return Button {
            linkedTaskNavigation = .detail(task.id)
        } label: {
            HStack(spacing: TFSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(2)
                    Label("\(relation) · \(status.text)", systemImage: status.icon)
                        .tfText(.meta)
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
        .listRowSeparator(.hidden)
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

    @ViewBuilder
    private var aiStructureStatusSection: some View {
        switch viewModel.aiStructureStatus {
        case .idle:
            EmptyView()
        case .processing:
            Section {
                HStack(spacing: TFSpacing.sm) {
                    ProgressView()
                    Text("AI структурирует задачу…")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AI структурирует задачу")
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        case .completed:
            Section {
                Label("Структура готова", systemImage: "checkmark.circle")
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            .listRowBackground(Color.tfBackground)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
    }

    private var linkedTaskQuickAddPresented: Binding<Bool> {
        Binding(get: { linkedTaskQuickAddViewModel != nil }, set: { if !$0 { linkedTaskQuickAddViewModel = nil } })
    }

    private var expandedLinkedTaskPresented: Binding<Bool> {
        Binding(get: { expandedLinkedTaskViewModel != nil }, set: { if !$0 { expandedLinkedTaskViewModel = nil } })
    }

    private func startLinkedTaskQuickAdd() {
        guard let taskID else { return }
        linkedTaskQuickAddViewModel = TaskFormViewModel(taskID: nil, parentTaskID: taskID, parentTaskTitle: viewModel.title, presetProjectID: viewModel.projectId)
    }

    private func expandLinkedTaskQuickAdd(_ linkedViewModel: TaskFormViewModel) {
        linkedTaskQuickAddViewModel = nil
        DispatchQueue.main.async { expandedLinkedTaskViewModel = linkedViewModel }
    }

    private func taskSectionHeader(_ title: String) -> some View {
        Text(title)
            .tfText(.title)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tfText)
            .textCase(nil)
            .underline()
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

        return VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(spacing: TFSpacing.md) {
                Button {
                    guard subtask.agentState != .review else { return }
                    Task { await viewModel.toggleSubtaskDone(subtask) }
                } label: {
                    subtaskMark(subtask, isRunning: isRunning)
                }
                .buttonStyle(.plain)
                .disabled(subtask.agentState == .review)
                // Отметка слева — иконка без текста, поэтому подпись задаём
                // явно и покрываем ОБЕ ветки `subtaskMark`: кольцо при running
                // и системную иконку во всех остальных состояниях.
                .accessibilityLabel(
                    isRunning
                        ? TFSubtaskState.running.label
                        : (subtask.done ? "Шаг выполнен" : "Отметить шаг выполненным")
                )
                .accessibilityHint(subtask.agentState == .review ? "" : "Переключает отметку шага")

                // Текст шага — обычное поле, как название и описание выше:
                // тап ставит курсор, правка уходит на сервер по вводу или
                // по уходу фокуса. Аккордеон с шевроном (раскрыть/свернуть
                // подробности) здесь больше не нужен — тап теперь означает
                // «правлю», а подробности показываются сами, когда есть.
                // Зачёркивания у сделанного шага нет: владелец 11.09.2026 —
                // «мне ж надо смотреть, как они называются». Что шаг закрыт,
                // видно по галочке слева.
                // Многострочное поле (длинные названия шагов видны целиком),
                // поэтому Return здесь переносит строку, а не сохраняет —
                // правка уходит на сервер, когда фокус покидает строку
                // (см. `.onChange(of: focusedSubtaskID)` у списка).
                TextField("Шаг", text: subtaskTitleBinding(subtask), axis: .vertical)
                    .lineLimit(1...)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .focused($focusedSubtaskID, equals: subtask.id)
            }

            if hasDetails {
                subtaskDetails(subtask, isRunning: isRunning)
                    .padding(.leading, 21 + TFSpacing.md)
            }
        }
        .listRowSeparator(.hidden)
    }

    /// Пока строку правят, текст живёт здесь, а не в модели: поллинг задачи
    /// (раз в 30 с) перезаписывает `viewModel.subtasks` целиком и стёр бы
    /// набранное на полуслове.
    private func subtaskTitleBinding(_ subtask: ApiSubtask) -> Binding<String> {
        Binding(
            get: { subtaskTitleDrafts[subtask.id] ?? subtask.title },
            set: { subtaskTitleDrafts[subtask.id] = $0 }
        )
    }

    private func commitSubtaskTitle(_ subtask: ApiSubtask) {
        guard let draft = subtaskTitleDrafts.removeValue(forKey: subtask.id) else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пустым названием шаг не затираем — это почти всегда промах, а не
        // намерение; строка возвращается к прежнему тексту.
        guard !trimmed.isEmpty, trimmed != subtask.title else { return }
        Task { await viewModel.renameSubtask(subtask, to: trimmed) }
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
                if !viewModel.activity.actions.isEmpty {
                    activityChips(viewModel.activity.actions)
                }
                if let text = viewModel.activity.text {
                    Text(text)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
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
                // Итог шага — главное, ради чего эту карточку открывают:
                // виден целиком и всегда, без сворачивания и усечения
                // (владелец 11.09.2026).
                Text(result).tfText(.action).foregroundStyle(Color.tfSub)
            }
            if isOwner, subtask.agentState == .review {
                Button("Принять") { Task { await viewModel.acceptSubtask(subtask) } }
                Button("Вернуть на доработку") { replyingSubtask = subtask }
            } else if isOwner, subtask.agentState == .blocked {
                Button("Ответить") { replyingSubtask = subtask }
            }
        }
    }

    /// Ярлычки действий агента у идущего шага: СНАЧАЛА число всех действий,
    /// ПОСЛЕ — последние пять иконок (владелец 21.09.2026: «в самом начале
    /// делаем число, а эти пять меняются после»). Раньше было наоборот —
    /// уникальные виды иконок, потом счётчик; владелец это забраковал.
    /// Никакой истории: живая картинка на момент просмотра.
    @ViewBuilder
    private func activityChips(_ actions: [ApiTaskActivityAction]) -> some View {
        HStack(spacing: TFSpacing.xs) {
            Text("\(actions.count) \(pluralActions(actions.count))")
                .tfText(.micro)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.sm)
                .frame(height: 24)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            ForEach(Array(actions.suffix(5)), id: \.id) { action in
                Image(systemName: activityIcon(action.kind))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tfDim)
                    .frame(width: 24, height: 24)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func activityIcon(_ kind: String) -> String {
        switch kind {
        case "read": "book"
        case "edit": "chevron.left.forwardslash.chevron.right"
        case "write": "doc.badge.plus"
        case "search": "magnifyingglass"
        case "run": "terminal"
        case "think": "brain"
        case "web": "globe"
        case "image": "photo"
        case "test": "checkmark.seal"
        case "build": "hammer"
        case "git": "arrow.triangle.branch"
        case "attach": "paperclip"
        default: "ellipsis"
        }
    }

    private func pluralActions(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "действий" }
        switch n % 10 {
        case 1: return "действие"
        case 2, 3, 4: return "действия"
        default: return "действий"
        }
    }

    /// Плоская строка ленты — без аватарок/цветных плашек `TaskJournalView`
    /// (та осталась только в мёртвом `TaskDetailScreen`), обычный `Text` в
    /// `Form`, текст события — тот же словарь §19.2 (`TaskJournalView.eventText`).
    @ViewBuilder
    private func nativeJournalRow(_ entry: TaskJournalEntry) -> some View {
        switch entry {
        case .comment(let comment):
            // Сообщение привязанного чата открывает саму переписку: лента
            // задачи показывает её, но продолжать разговор нужно в чате
            // (владелец 21.09.2026: «чтобы не комментарии писать в самой
            // задаче, а в чате переписываться»).
            if comment.isFromChat, let chatID = comment.chatID {
                NavigationLink(value: AppRoute.roleChat(id: chatID)) {
                    journalCommentBody(comment)
                }
            } else {
                journalCommentBody(comment)
            }
        case .event(let event):
            // Кто сделал — обязательно (владелец 22.09.2026: безличное
            // «выполнил шаг» не говорит, чья это работа). Нет автора —
            // действие системы. Имя и действие разделены точкой, чтобы не
            // согласовывать глагол с родом («Система взял»).
            HStack(alignment: .firstTextBaseline) {
                (Text(event.actorName?.isEmpty == false ? event.actorName! : "Система").fontWeight(.medium)
                    + Text(" · ")
                    + Text(TaskJournalView.eventText(event)))
                    .tfText(.action).foregroundStyle(Color.tfSub)
                Spacer()
                if let date = event.createdAtDate {
                    Text(TaskDateText.relativeTime(date)).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
        }
    }

    /// Тело комментария ленты — общее для обычного комментария и для сообщения
    /// привязанного чата (у второго только добавляется пометка).
    @ViewBuilder
    private func journalCommentBody(_ comment: ApiComment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(comment.userName?.isEmpty == false ? comment.userName! : "Система")
                    .tfText(.body).fontWeight(.medium)
                if comment.isFromChat {
                    // Пометка нейтральная: синий акцент в приложении не используется.
                    TFPill("из чата", color: Color.tfSub)
                }
                Spacer()
                if let date = comment.createdAtDate {
                    Text(TaskDateText.relativeTime(date)).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
            Text(comment.text).tfText(.action).foregroundStyle(Color.tfSub)
            // ВЛОЖЕНИЯ КОММЕНТАРИЯ. 11.09.2026: лента рисовала только
            // текст, и приложенные кадры в приложении не показывались
            // вовсе. Чинить сначала полез в `TaskJournalView.commentCard`
            // — а он живёт в мёртвом `TaskDetailScreen` и не исполняется;
            // рабочая лента здесь. Картинки грузит `ChatAttachmentImage`
            // (умеет ходить с авторизацией, обычный AsyncImage к этому
            // эндпоинту не годится), прочие файлы — строкой с именем.
            if let attachments = comment.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(attachments) { attachment in
                        if attachment.mime?.hasPrefix("image/") == true {
                            ChatAttachmentImage(
                                attachmentId: attachment.id,
                                fileName: attachment.fileName
                            )
                        } else {
                            Label(attachment.fileName, systemImage: "paperclip")
                                .tfText(.meta)
                                .foregroundStyle(Color.tfSub)
                        }
                    }
                }
                .padding(.top, 4)
            }
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

    /// Подпись исполнителя: имя владельца (карточка на человеке), имя
    /// выбранной роли либо «Автоматически» (LOCK-178).
    private var selectedRoleTitle: String {
        if let me = session.currentUser, viewModel.assigneeId == me.id {
            return me.name
        }
        guard let role = viewModel.ownerSelectedRole,
              let profile = viewModel.roles.first(where: { $0.role == role }) else {
            return "Автоматически"
        }
        return profile.title
    }

    private func agentStateText(_ state: AgentState) -> String {
        switch state {
        case .inProgress: "В работе"
        case .blocked: "Заблокирована"
        case .review: "На проверке"
        }
    }

    /// Цвет подписи состояния в шапке. «На проверке»: серая — ждёт
    /// проверяющего, синяя — отправлена ему и он работает, зелёная — он
    /// вынес вердикт (владелец 22.09.2026). Считаем по ленте после
    /// последнего ухода в review: прошлые круги проверки не в счёт.
    private func agentStateColor(_ state: AgentState) -> Color {
        switch state {
        case .blocked:
            return .orange
        case .inProgress:
            return .tfSub
        case .review:
            let events = viewModel.journalEntries.compactMap { entry -> ApiTaskEvent? in
                if case .event(let event) = entry { return event }
                return nil
            }
            // `journalEntries` идут от новых к старым: всё, что новее
            // последнего ухода в review, лежит ДО него.
            let end = events.firstIndex { $0.kind == "state_changed" && $0.toValue == "review" }
                ?? events.endIndex
            let current = events[..<end]
            if current.contains(where: { $0.kind == "review_recorded" }) { return .tfGreen }
            if current.contains(where: {
                $0.kind == "reviewer_sent" || ($0.kind == "run_requested" && $0.field == "reviewer")
            }) {
                return .tfBlue
            }
            return .tfSub
        }
    }

    private func agentStateIcon(_ state: AgentState) -> String {
        switch state {
        case .inProgress: "play.circle.fill"
        case .blocked: "exclamationmark.triangle.fill"
        case .review: "eye.fill"
        }
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
                        Task { await viewModel.structureWithAI() }
                    } label: {
                        Label("Структурировать с AI", systemImage: "sparkles")
                    }
                    .disabled(viewModel.aiStructureStatus.isProcessing)
                }
                if isOwner, let state = viewModel.agentState {
                    ownerActionMenuItems(state)
                }
                if isOwner {
                    // Ручной разовый запуск: поднять исполнителя или
                    // верификатора на этой карточке, не включая будильник.
                    Button {
                        Task {
                            if await viewModel.runAgent(mode: "executor") {
                                toast = TaskToastMessage("Исполнитель поднят — возьмёт карточку")
                            }
                        }
                    } label: {
                        Label("Запустить исполнителя", systemImage: "play.circle")
                    }
                    .disabled((viewModel.assigneeId ?? "").isEmpty)
                    if viewModel.agentState == .review {
                        Button {
                            Task {
                                if await viewModel.runAgent(mode: "reviewer") {
                                    toast = TaskToastMessage("Верификатор поднят — проверит карточку")
                                }
                            }
                        } label: {
                            Label("Отправить на проверку верификатору", systemImage: "checkmark.seal")
                        }
                    }
                }
                // Серия повтора завершилась на конце года — одним тапом
                // продлеваем на следующий (владелец 20.09.2026).
                if isOwner, viewModel.seriesEnded {
                    Button {
                        Task {
                            if await viewModel.extendRepeat() {
                                toast = TaskToastMessage("Серия продлена на следующий год")
                            }
                        }
                    } label: {
                        Label("Продлить на год", systemImage: "calendar.badge.plus")
                    }
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

                    // Глубокое исследование (миграция 052 сервера
                    // New-Todoist). Тумблер-отметка и кнопка запуска
                    // серверного конвейера: он сам собирает источники,
                    // проверяет их и кладёт отчёт в секцию «Отчёты».
                    Button {
                        Task { await viewModel.toggleNeedsResearch(taskStore: taskStore) }
                    } label: {
                        Label(
                            viewModel.needsResearch
                                ? "Глубокое исследование: включено"
                                : "Нужно глубокое исследование",
                            systemImage: viewModel.needsResearch
                                ? "magnifyingglass.circle.fill"
                                : "magnifyingglass"
                        )
                    }
                    if viewModel.needsResearch {
                        Button {
                            Task {
                                if await viewModel.startResearch() {
                                    toast = TaskToastMessage("Исследование запущено — отчёт появится в карточке")
                                }
                            }
                        } label: {
                            Label("Запустить исследование", systemImage: "sparkles")
                        }
                    }
                }
                // Закрепление переехало сюда из строки списка проекта
                // (владелец 11.09.2026): «закреплять я буду в самой карточке,
                // через три точки, а не рисовать скрепки в каждой строке».
                Button {
                    Task { await viewModel.togglePinned(taskStore: taskStore) }
                } label: {
                    Label(
                        viewModel.pinned ? "Открепить задачу" : "Закрепить задачу",
                        systemImage: viewModel.pinned ? "pin.slash" : "pin"
                    )
                }
                Menu {
                    Button { isAttachmentPickerPresented = true } label: {
                        Label("С iPhone", systemImage: "iphone")
                    }
                    Button { isKnowledgePickerPresented = true } label: {
                        Label("Из базы знаний", systemImage: "books.vertical")
                    }
                } label: {
                    Label("Прикрепить файл", systemImage: "paperclip")
                }
                Button { outputDynamicIsland() } label: {
                    Label("Вывести в Dynamic Island", systemImage: "bolt.badge.a")
                }
                Button { saveAsTemplate() } label: {
                    Label("Сохранить как шаблон", systemImage: "doc.on.doc")
                }
                if taskID != nil {
                    Button { isExistingTaskPickerPresented = true } label: {
                        Label("Связать существующую задачу", systemImage: "link.badge.plus")
                    }
                }
                Divider()
                Button("Удалить задачу", systemImage: "trash", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.tfText)
            }
            .accessibilityLabel("Ещё")
        }
    }

    /// Перенесено буквально из `TaskDetailScreen.ownerActionMenuItems` —
    /// та же логика (§19.2 AgentOwnerActions), другой источник состояния.
    @ViewBuilder
    private func ownerActionMenuItems(_ state: AgentState) -> some View {
        switch state {
        case .review:
            Button { Task { await viewModel.performOwnerAction(.acceptReview, comment: nil, taskStore: taskStore) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
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

    private func deleteCurrentTask() async {
        guard let taskID, await taskStore.delete(taskId: taskID) else { return }
        dismiss()
    }

    private var taskKeyboardDismissButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
        }
        .accessibilityLabel("Скрыть клавиатуру")
        .accessibilityLabel("Скрыть клавиатуру")
    }

    private var taskKeyboardDictationButton: some View {
        Button {
            Task { await toggleDictation() }
        } label: {
            Group {
                switch dictation.recordingState {
                case .recording:
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: true)
                case .transcribing:
                    ProgressView()
                default:
                    Image(systemName: "mic.fill")
                }
            }
        }
        .disabled(dictation.recordingState == .transcribing)
        .accessibilityLabel("Голосовой ввод")
    }

    private func toggleDictation() async {
        switch dictation.recordingState {
        case .idle, .failed:
            await dictation.startRecording()
        case .recording:
            guard let text = await dictation.stopRecordingAndTranscribe() else { return }
            switch dictationTarget {
            case .title:
                viewModel.title = appendedDictation(text, to: viewModel.title)
            case .description:
                viewModel.taskDescription = appendedDictation(text, to: viewModel.taskDescription)
            case .comment:
                viewModel.commentText = appendedDictation(text, to: viewModel.commentText)
            case .newSubtask:
                newSubtaskTitle = appendedDictation(text, to: newSubtaskTitle)
            case .subtask(let id):
                guard let subtask = viewModel.subtasks.first(where: { $0.id == id }) else { return }
                subtaskTitleDrafts[id] = appendedDictation(text, to: subtaskTitleDrafts[id] ?? subtask.title)
            }
        case .transcribing:
            break
        }
    }

    private func appendedDictation(_ text: String, to existing: String) -> String {
        guard !existing.isEmpty else { return text }
        return existing + (existing.hasSuffix(" ") ? "" : " ") + text
    }

    // MARK: - Тело

    private var aiStructureButton: some View {
        Button {
            Task { await viewModel.structureWithAI() }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                if viewModel.aiStructureStatus.isProcessing {
                    ProgressView()
                    Text("Структурирую…").tfText(.body).fontWeight(.semibold)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                    Text("Структурировать с AI").tfText(.body).fontWeight(.semibold)
                }
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
        .disabled(viewModel.aiStructureStatus.isProcessing)
        .accessibilityLabel(viewModel.aiStructureStatus.isProcessing ? "AI структурирует задачу" : "Структурировать задачу с AI")
    }

    /// Шаги — одинаково в создании и в готовой задаче. Владелец 11.09.2026:
    /// «просто тапаю и редактирую, как саму задачу, как описание» — никаких
    /// кнопок «изменить», плюсов, галочек и крестиков. Разница только в
    /// источнике: у новой задачи это черновики в памяти, у существующей —
    /// шаги с сервера.
    private var subtasksSection: some View {
        Section {
            if viewModel.isEditing {
                ForEach(viewModel.subtasks) { subtask in
                    nativeSubtaskRow(subtask)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach($viewModel.subtaskDrafts) { $draft in
                    TextField("Шаг", text: $draft.title, axis: .vertical)
                        .lineLimit(1...)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .listRowSeparator(.hidden)
                }
                .onDelete { viewModel.subtaskDrafts.remove(atOffsets: $0) }
            }
            newSubtaskRow
        } header: {
            taskSectionHeader("Подзадачи")
        }
        .listRowBackground(Color.tfBackground)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
    }

    /// Последняя строка списка шагов — пустое поле вместо кнопки с диалогом.
    /// Владелец 11.09.2026: «нажимаю „Добавить подзадачу“ — какая-то форма
    /// пытается открыться и сразу умирает». Диалога больше нет: написал в
    /// строке, нажал ввод — шаг добавлен, поле осталось пустым и в фокусе,
    /// так что следующий пишется сразу (как в «Напоминаниях»).
    private var newSubtaskRow: some View {
        // Однострочное намеренно: здесь Return должен ДОБАВЛЯТЬ шаг, а в
        // многострочном поле он вставлял бы перенос в название.
        TextField("Добавить подзадачу", text: $newSubtaskTitle)
            .focused($isNewSubtaskFocused)
            .tfText(.action)
            .foregroundStyle(Color.tfDim)
            .submitLabel(.return)
            .onSubmit(addSubtaskInline)
            .listRowSeparator(.hidden)
    }

    private func addSubtaskInline() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newSubtaskTitle = ""
        guard !title.isEmpty else { return }
        if viewModel.isEditing {
            Task { await viewModel.addSubtask(title) }
        } else {
            viewModel.subtaskDrafts.append(SubtaskDraft(title: title))
        }
        // Фокус после добавления возвращаем в ту же строку: список шагов
        // обычно пишут подряд, а не по одному с перезаходом.
        isNewSubtaskFocused = true
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
        // Карточку закрыли, не выходя из строки шага — правка не должна
        // пропасть вместе с экраном.
        for subtask in viewModel.subtasks where subtaskTitleDrafts[subtask.id] != nil {
            commitSubtaskTitle(subtask)
        }
        Task { await saveExistingEdits() }
    }

    private func reportSubtitle(_ report: TaskReport) -> String {
        var parts: [String] = []
        if let author = report.authorName, !author.isEmpty { parts.append(author) }
        if let date = report.createdAtDate { parts.append(TaskDateText.relativeTime(date)) }
        return parts.joined(separator: " · ")
    }

    private func handleAttachmentImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            replaceAttachmentTarget = nil
            return
        }
        let old = replaceAttachmentTarget
        replaceAttachmentTarget = nil
        Task {
            await viewModel.attachments.add(url: url)
            if let old { await viewModel.attachments.removeUploaded(old) }
        }
    }

    /// Приложить документ из базы знаний: забираем его markdown и кладём
    /// файлом .md к задаче — тем же путём, что и любой другой файл.
    private func attachKnowledgeNote(noteID: String, title: String) async {
        do {
            let note = try await APIClient().note(id: noteID, format: "markdown")
            let markdown = note.markdown ?? ""
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                viewModel.attachments.errorMessage = "Документ пуст"
                return
            }
            let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String((base.isEmpty ? "Документ" : base).prefix(80)) + ".md"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try markdown.data(using: .utf8)?.write(to: url, options: .atomic)
            await viewModel.attachments.add(url: url)
        } catch {
            viewModel.attachments.errorMessage = "Не удалось приложить документ"
        }
    }

    private func loadScreen() async {
        await viewModel.loadIfNeeded()
        await viewModel.loadRoles()
        if taskStore.tasks.isEmpty { await taskStore.load() }
        if projectStore.projects.isEmpty { await projectStore.load() }
        if labelStore.labels.isEmpty { await labelStore.load() }
        if viewModel.startDictation { isTitleFocused = true }
        await viewModel.loadActivity()
        await viewModel.loadReports()
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
    @Binding var runRepeat: String
    @Binding var repeatUntil: Date?

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

            // Время не задано — старт всё равно будет, в 09:00. Скажем прямо.
            if dueDate != nil && startMinutes == nil {
                Text("Старт по умолчанию — 9:00. Измените время, если нужно.")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
            }

            if dueDate != nil {
                Picker("Продолжительность", selection: $durationMin) {
                    Text("Не указана").tag(Int?.none)
                    ForEach(Self.durationOptions, id: \.minutes) { option in
                        Text(option.label).tag(Optional(option.minutes))
                    }
                }

                // Повтор: одна карточка за раз, следующая создаётся, когда
                // текущая закрыта. Работает до конца календарного года —
                // дальше назначается заново.
                Picker("Повтор", selection: $runRepeat) {
                    Text("Не повторять").tag("none")
                    Text("Ежедневно").tag("daily")
                    Text("По будням").tag("weekdays")
                    Text("Еженедельно").tag("weekly")
                    Text("Ежемесячно").tag("monthly")
                }
                if runRepeat != "none" {
                    DatePicker("Повторять до", selection: untilBinding, displayedComponents: .date)
                    Text("Повтор идёт до конца года, дальше назначьте заново.")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
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

    /// «Повторять до»: если не задано — показываем конец текущего года
    /// (дальше серия всё равно не идёт, владелец 20.09.2026).
    private var untilBinding: Binding<Date> {
        Binding(
            get: { repeatUntil ?? Self.yearEnd },
            set: { repeatUntil = $0 }
        )
    }

    private static var yearEnd: Date {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = cal.component(.year, from: Date())
        comps.month = 12
        comps.day = 31
        return cal.date(from: comps) ?? Date()
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

/// Мягкая верхняя кромка прокрутки (iOS 26+).
///
/// Вынесено отдельным модификатором, потому что `.scrollEdgeEffectStyle`
/// доступен с iOS 26, а цель сборки — iOS 18: `if #available` внутри цепочки
/// модификаторов дал бы две разные ветки типа и не собрался бы.
///
/// На системах старше 26 модификатор ничего не делает — кромка остаётся
/// системной по умолчанию (жёсткой), экран при этом полностью рабочий.
struct TFSoftTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
