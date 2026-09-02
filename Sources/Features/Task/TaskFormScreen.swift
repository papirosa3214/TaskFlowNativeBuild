import SwiftUI

/// Форма задачи — spec/SCREENS-1.md §5.5, обслуживает `/task/new` и
/// `/task/:id/edit` ОДНОЙ структурой (различие — заголовок секции и способ
/// отправки патча). Имя и параметр — контракт `INTEGRATION.md`, буквально.
///
/// ⚠️ 31.08.2026, задача «компактное создание»: полноэкранный бланк при
/// СОЗДАНИИ (`taskID == nil`) владелец назвал «формой заявки на анкету» —
/// заменён компактной панелью `QuickAddTaskView` (см. файл рядом), эта
/// структура при создании теперь ТОЛЬКО хост для неё и площадка для
/// «развернуть». Редактирование (`taskID != nil`) — без изменений, старое
/// полноэкранное тело (`fullFormBody`) как было.
///
/// ⚠️ 02.09.2026, владелец: открытие ЛЮБОЙ существующей задачи (из списков,
/// досок, чата и т.п.) ведёт СРАЗУ сюда — отдельный экран-просмотр
/// `TaskDetailScreen` из этого пути убран (`routeDestination(.taskDetail)`,
/// `TodayScreen` шторка). Меню «…» с действиями владельца (принять/вернуть,
/// Dynamic Island, шаблон) перенесено сюда же — см. `ownerActionMenuItems`.
struct TaskFormScreen: View {
    let taskID: String?

    @State private var viewModel: TaskFormViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(LabelStore.self) private var labelStore
    @Environment(SessionStore.self) private var session
    @FocusState private var isTitleFocused: Bool

    /// Перенесено из `TaskDetailScreen` вместе с меню «…».
    @State private var pendingAction: AgentOwnerActionKind?
    @State private var actionComment = ""
    @State private var toast: TaskToastMessage?
    /// 02.09.2026: «Прикрепить файл» — пункт меню «…» при правке (не своя
    /// строка в теле формы, см. `AttachmentsFieldView.showAddButton`).
    @State private var isAttachmentPickerPresented = false

    /// Владелец 02.09.2026: открытие СУЩЕСТВУЮЩЕЙ задачи по умолчанию — это
    /// чтение, не правка. Поля неактивны, в шапке только крестик и «…»;
    /// «Изменить» в этом меню — НЕ переключатель на месте, а НАСТОЯЩИЙ пуш
    /// (владелец прямо указал: «была именно эта выдвигающаяся нативная
    /// хрень» — родной slide-in `NavigationStack`, как раньше был переход
    /// TaskDetailScreen → TaskFormScreen). Пушим тот же экран второй раз,
    /// сразу в редактируемом виде — см. `pushEditScreen` и `editingExisting`.
    /// При создании (оба init'а — прямой и `expandingFrom`) правка нужна
    /// сразу, поэтому `false`.
    @State private var isReadOnly: Bool
    /// Триггер пуша экрана правки (см. комментарий у `isReadOnly`).
    @State private var pushEditScreen = false

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
    /// `/task/new?dictate=1` из `CreateMenu` веба). Диктовку саму не
    /// подключаю (в проекте нет живого ASR-провода на native, см.
    /// `NATIVE-PARTS.md`) — только состояние: поле названия сфокусировано,
    /// кнопка микрофона показана (по прямой просьбе оркестратора).
    init(taskID: String?, presetDueToday: Bool = false, startDictation: Bool = false) {
        self.taskID = taskID
        self._viewModel = State(initialValue: TaskFormViewModel(taskID: taskID, presetDueToday: presetDueToday, startDictation: startDictation))
        self._showQuickAdd = State(initialValue: taskID == nil)
        self._isExpanded = State(initialValue: false)
        self._isReadOnly = State(initialValue: taskID != nil)
    }

    /// Пуш-назначение из «…» → «Изменить» (см. `isReadOnly`) — тот же экран,
    /// но сразу в правке, своя вью-модель (перечитывает задачу заново, тем
    /// самым подхватывая правки владельца, если они уже были).
    init(editingExisting taskID: String) {
        self.taskID = taskID
        self._viewModel = State(initialValue: TaskFormViewModel(taskID: taskID))
        self._showQuickAdd = State(initialValue: false)
        self._isExpanded = State(initialValue: false)
        self._isReadOnly = State(initialValue: false)
    }

    /// «Развернуть» из `QuickAddTaskView` — тот же экран, СРАЗУ с готовой
    /// вью-моделью и в режиме полной формы (сохранение всё ещё «создание»:
    /// `viewModel.taskID == nil`, поэтому различаем через `isExpanded`, не
    /// через `isEditing`).
    init(expandingFrom viewModel: TaskFormViewModel) {
        self.taskID = viewModel.taskID
        self._viewModel = State(initialValue: viewModel)
        self._showQuickAdd = State(initialValue: false)
        self._isExpanded = State(initialValue: true)
        self._isReadOnly = State(initialValue: false)
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
                .sheet(isPresented: $showQuickAdd, onDismiss: {
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
                }
        }
    }

    private var fullFormBody: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingTask {
                TFLoading(.block)
                Spacer()
            } else if viewModel.notFound {
                Spacer()
                TFEmptyState(text: "Задача не найдена")
                Spacer()
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
        // В режиме чтения — пусто, не название задачи: оно уже своей строкой
        // в теле (`titleField`), системная шапка дублировала бы его вторым
        // заголовком сверху (та же причина, что была в `TaskDetailScreen`).
        .tfNativeHeader(isReadOnly ? "" : (viewModel.title.isEmpty ? "Новая задача" : viewModel.title), displayMode: .inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.tfText)
                }
            }
            if viewModel.isEditing {
                if isReadOnly {
                    // Чтение — просто «…», как и было.
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { pushEditScreen = true } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                            if isOwner, let state = viewModel.agentState {
                                ownerActionMenuItems(state)
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
                } else {
                    // Правка — см. `editingToolbarItems`.
                    editingToolbarItems
                }
            } else {
                // Создание — без «…», без пилюли, как было.
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
        .sheet(item: $pendingAction) { action in
            TFBottomSheetContent(title: "Комментарий", onClose: { pendingAction = nil }) {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    TFTextField(action.commentRequired ? "Комментарий (обязателен)" : "Комментарий (необязательно)", text: $actionComment)
                    TFButton("Отправить", variant: .primary, isEnabled: !action.commentRequired || !actionComment.trimmingCharacters(in: .whitespaces).isEmpty) {
                        Task { await viewModel.performOwnerAction(action, comment: actionComment.isEmpty ? nil : actionComment) }
                        actionComment = ""
                        pendingAction = nil
                    }
                }
                .padding(.bottom, TFSpacing.xl)
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Color.tfCard)
        }
        .taskToast($toast)
        .fileImporter(isPresented: $isAttachmentPickerPresented, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await viewModel.attachments.add(url: url) }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.loadAgents()
            if viewModel.startDictation { isTitleFocused = true }
        }
        // Пуш на редактируемый экран — родной slide-in `NavigationStack`,
        // см. комментарий у `isReadOnly`.
        .navigationDestination(isPresented: $pushEditScreen) {
            if let taskID { TaskFormScreen(editingExisting: taskID) }
        }
        .onChange(of: pushEditScreen) { wasPushed, isPushed in
            // Вернулись с пуша (сохранили или смахнули) — перечитать задачу,
            // экран под пушем сам `.task` повторно не запускает.
            if wasPushed, !isPushed { Task { await viewModel.loadIfNeeded() } }
        }
    }

    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// «…» + галочка для режима правки — 02.09.2026, владелец: «уберите
    /// кашу из трёх кнопок» (было: AI-кнопка + «…» + «Готово» текстом).
    /// Без самодельного фона/капсулы/разделителя — два обычных
    /// `ToolbarItem` рядом, iOS 26 сама рисует их одной стеклянной
    /// пилюлей (Liquid Glass), не нужно имитировать вручную.
    /// «Структурировать с AI» — пункт этого же меню (владелец сначала убрал
    /// её из правки, затем вернул обратно сюда же, пунктом, не кнопкой).
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
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await submit() }
            } label: {
                if viewModel.isSaving {
                    TFLoading(.inline)
                } else {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.tfText)
                }
            }
            .disabled(!viewModel.isSaveEnabled)
        }
    }

    /// Перенесено буквально из `TaskDetailScreen.ownerActionMenuItems` —
    /// та же логика (§19.2 AgentOwnerActions), другой источник состояния.
    @ViewBuilder
    private func ownerActionMenuItems(_ state: AgentState) -> some View {
        switch state {
        case .review:
            Button { Task { await viewModel.performOwnerAction(.acceptReview, comment: nil) } } label: {
                Label("Принять", systemImage: "checkmark")
            }
            Button { pendingAction = .returnToWorkFromReview } label: {
                Label("Вернуть на доработку", systemImage: "arrow.uturn.backward")
            }
        case .blocked:
            Button { pendingAction = .replyAndReturnFromBlocked } label: {
                Label("Ответить и вернуть в работу", systemImage: "arrowshape.turn.up.left")
            }
            Button { Task { await viewModel.performOwnerAction(.acceptAndClose, comment: nil) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
        case .inProgress:
            Button { Task { await viewModel.performOwnerAction(.returnToWorkFromInProgress, comment: nil) } } label: {
                Label("Вернуть на доработку", systemImage: "arrow.uturn.backward")
            }
            Button { Task { await viewModel.performOwnerAction(.acceptAndClose, comment: nil) } } label: {
                Label("Принять и закрыть задачу", systemImage: "checkmark.circle")
            }
        }
    }

    private func outputDynamicIsland() {
        // Перенесено из `TaskDetailScreen` буквально — тост по спеке, без
        // реального ActivityKit (Live Activity живёт в отдельном таргете).
        toast = TaskToastMessage("Задача выведена в Dynamic Island")
    }

    private func saveAsTemplate() {
        // Перенесено из `TaskDetailScreen` буквально — на сервере нет
        // эндпоинта шаблонов, тост показывается по спеке.
        toast = TaskToastMessage("Задача сохранена в шаблоны")
    }

    /// `MicKeyboardBar` — spec/SCREENS-2.md §0.7: плавающая круглая кнопка
    /// 44×44 над клавиатурой, полупрозрачное стекло. Здесь ТОЛЬКО видимость
    /// по фокусу поля названия — само распознавание не подключено (см. header).
    private var micKeyboardBar: some View {
        Button {
            // Не подключено — см. комментарий у `init`.
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.tfText)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(TFTapScaleStyle())
        .padding(.trailing, TFSpacing.lg)
        .padding(.bottom, TFSpacing.lg)
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
            titleField
            noteSection
            subtasksSection
            // 02.09.2026, владелец: «зачем эта здоровая хрень, когда файлов
            // нет» — строка показывается только если есть что показать;
            // добавление файла теперь пункт «…» (`isAttachmentPickerPresented`).
            if !viewModel.attachments.uploaded.isEmpty || !viewModel.attachments.pending.isEmpty {
                AttachmentsFieldView(controller: viewModel.attachments, showAddButton: false)
                    .disabled(isReadOnly)
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
            .disabled(isReadOnly)

            AssigneeFieldView(agents: viewModel.agents, selectedAgentId: $viewModel.assigneeId)
                .disabled(isReadOnly)

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
            .foregroundStyle(.white)
            .padding(.horizontal, TFSpacing.lg)
            .padding(.vertical, TFSpacing.sm)
            .background(
                LinearGradient(colors: [.tfPurple, .tfPink], startPoint: .leading, endPoint: .trailing)
            )
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
            .disabled(isReadOnly)
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
                .disabled(isReadOnly)
                .lineLimit(1...)
        }
    }

    /// Чтение (по умолчанию, существующая задача) — статус-карточки агентов
    /// с разворотом по тапу (`SubtaskFeedView`, как в старом TaskDetailScreen:
    /// владелец 02.09.2026 прямо указал, что эта «выдвигающаяся» деталь была
    /// потеряна при переезде на форму, — вернул её сюда). Правка (после
    /// «Изменить», или создание) — список для переименования/удаления/добавления.
    @ViewBuilder
    private var subtasksSection: some View {
        if isReadOnly {
            if !viewModel.subtasks.isEmpty {
                TFCollapsibleSection(
                    title: "Подзадачи",
                    trailingBadge: "\(viewModel.subtasks.count { $0.done }) из \(viewModel.subtasks.count)",
                    isExpanded: $isSubtasksExpanded
                ) {
                    SubtaskFeedView(
                        subtasks: viewModel.subtasks,
                        isOwner: isOwner,
                        onToggleDone: { subtask in Task { await viewModel.toggleSubtaskDone(subtask) } },
                        onSubmitReply: { subtask, text in Task { await viewModel.replyToSubtask(subtask, text: text) } },
                        onAccept: { subtask in Task { await viewModel.acceptSubtask(subtask) } }
                    )
                }
            }
        } else {
            TFCollapsibleSection(title: "Подзадачи", isExpanded: $isSubtasksExpanded) {
                if viewModel.isEditing {
                    SubtaskEditListView(
                        subtasks: viewModel.subtasks,
                        onReorder: { newOrder in Task { await viewModel.reorderSubtasks(newOrder) } },
                        onRename: { subtask, newTitle in Task { await viewModel.renameSubtask(subtask, to: newTitle) } },
                        onDelete: { subtask in Task { await viewModel.deleteSubtask(subtask) } },
                        onAdd: { title in Task { await viewModel.addSubtask(title) } }
                    )
                } else {
                    SubtaskDraftListView(drafts: $viewModel.subtaskDrafts)
                }
            }
        }
    }

    private func submit() async {
        if await viewModel.save(taskStore: taskStore) {
            dismiss()
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
