import Foundation
import Observation

enum TaskAIStructureStatus: Equatable {
    case idle
    case processing
    case completed
    case failed(String)

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

// Вью-модель формы задачи — spec/SCREENS-1.md §5.5. Своя `APIClient()`, а не
// из окружения: `TaskFlowApp` кладёт в `.environment` только сторы, сам
// клиент нигде не раздаётся (см. отчёт — предложение добавить его в
// environment для будущих экранов).
@MainActor
@Observable
final class TaskFormViewModel {
    let collaborationPlanState: CollaborationPlanState
    var taskID: String?
    private let apiClient: APIClient
    @ObservationIgnored private var activityLoad: Task<Void, Never>?
    @ObservationIgnored private var activityRequestedRevision: Int?

    /// AST-форма названия для `BlockDocumentEditor` — ровно тот же редактор
    /// и тот же приём, что уже у описания ниже (владелец 30.09.2026:
    /// «вся карточка как описание»). `title` — проекция в строку: get
    /// кодирует блоки в markdown, set парсит входящий markdown (с сервера,
    /// от AI-структуризатора) в блоки. Старый код, читающий `title` как
    /// String, продолжает работать без правок.
    var titleBlocks: [NoteBlock] = [NoteBlock(kind: .paragraph)]
    var title: String {
        // Название без оформления — простым текстом (владелец 14.10.2026):
        // кодировщик экранирует «.», «-», «(», «[», и любое сохранение
        // карточки отправляло «веб\-приложения» вместо «веб-приложения» —
        // слэши накопились в 36 названиях.
        get {
            if titleBlocks.count == 1, case .paragraph = titleBlocks[0].kind,
               titleBlocks[0].runs.allSatisfy({ !$0.bold && !$0.italic && !$0.underline && !$0.strike && !$0.highlight && !$0.code && $0.linkHref == nil }) {
                return titleBlocks[0].runs.map(\.text).joined()
            }
            return MarkdownEncoder.encode(titleBlocks)
        }
        set {
            let parsed = MarkdownParser.parse(newValue)
            titleBlocks = parsed.isEmpty ? [NoteBlock(kind: .paragraph)] : parsed
        }
    }
    /// AST-форма описания для `BlockDocumentEditor` — того же редактора, что
    /// в заметке (LOCK-142). Строка
    /// `taskDescription` ниже — проекция: get кодирует блоки в markdown,
    /// set парсит входящий markdown (от сервера, от AI-структуризатора)
    /// в блоки. Старый код, читающий `taskDescription` как String,
    /// продолжает работать без правок.
    var taskDescriptionBlocks: [NoteBlock] = [NoteBlock(kind: .paragraph)] {
        // Любая запись массива (в том числе через `Binding` редактора) сбрасывает
        // кэш собранного markdown — иначе описание в карточке перестало бы
        // совпадать с тем, что в полях.
        didSet { cachedDescriptionMarkdown = nil }
    }

    /// Собранный markdown описания. Раньше `MarkdownEncoder.encode` срабатывал на
    /// каждый доступ к `taskDescription`, а он читается несколько раз за проход
    /// `body` карточки (подпись, сравнение с серверным описанием, автосохранение).
    private var cachedDescriptionMarkdown: String?

    var taskDescription: String {
        get {
            if let cached = cachedDescriptionMarkdown { return cached }
            let encoded = MarkdownEncoder.encode(taskDescriptionBlocks)
            cachedDescriptionMarkdown = encoded
            return encoded
        }
        set {
            let parsed = MarkdownParser.parse(newValue)
            taskDescriptionBlocks = parsed.isEmpty ? [NoteBlock(kind: .paragraph)] : parsed
            cachedDescriptionMarkdown = newValue
        }
    }

    /// Сравниваем исходник; при загрузке сохраняем серверную строку без перекодирования.
    func descriptionMatches(_ serverDescription: String?) -> Bool {
        if taskDescription == (serverDescription ?? "") { return true }
        guard serverDescription == originalTask?.description,
              let serverDocument = try? NoteDocument.fromServer(originalTask?.descriptionDocument) else { return false }
        return MarkdownEncoder.encode(taskDescriptionBlocks) == MarkdownEncoder.encode(serverDocument.blocks)
    }

    private func adoptTitleDocument(from task: ApiTask) throws {
        titleBlocks = try NoteDocument.fromServer(task.titleDocument).blocks
    }

    private func adoptDescriptionDocument(from task: ApiTask) throws {
        taskDescriptionBlocks = try NoteDocument.fromServer(task.descriptionDocument).blocks
        cachedDescriptionMarkdown = task.description ?? ""
    }

    var subtaskDrafts: [SubtaskDraft] = [] // режим create
    var subtasks: [ApiSubtask] = []        // режим edit — с сервера
    var dueDate: Date?
    var startMinutes: Int?
    var durationMin: Int?
    var projectId: String?
    var priority: TaskPriority = .low
    var selectedLabelIds: Set<String> = []
    var assigneeId: String?
    var requiresReviewerReview = true

    /// Повтор карточки: none|daily|weekdays|weekly|monthly и «до даты».
    var runRepeat: String = "none"
    var repeatUntil: Date?

    /// Создать из этой задачи рутину: рутина сама создаёт новые карточки по
    /// расписанию (правило — поле «повтор», время — поле «время запуска»).
    /// Только для новой карточки: у уже созданной рутины быть не может.
    var routineEnabled = false
    /// Что вышло при создании рутины (задача к этому моменту уже создана).
    var routineNotice: String?

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Moscow")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// Имя того, кто завёл карточку — только для показа, менять его нельзя.
    var creatorName: String?
    /// ID создателя — пробрасываем в `TFAvatar`, чтобы для роли-агента
    /// показывать рисунок роли вместо инициалов (LOCK-248). Только чтение,
    /// на редактирование не идёт: `creatorId` ставит сервер.
    var creatorId: String?
    var attachments: TaskAttachmentsController

    // Полноценные связанные задачи (`tasks.parent_id`) — отдельная модель от
    // чек-листа `subtasks`. У дочерней задачи остаются собственные статус,
    // срок, исполнитель и остальные поля обычной задачи.
    var parentId: String?
    var parentTitle: String?
    var parentTask: ApiTask?
    var childTasks: [ApiTask] = []
    var ancestorTaskIDs: Set<String> = []

    var isLoadingTask = false
    var isSaving = false
    var notFound = false
    var loadErrorMessage: String?
    var saveErrorMessage: String?
    var aiStructureStatus: TaskAIStructureStatus = .idle
    var directoriesErrorMessage: String?
    /// Профили ролей для выбора исполнителя (LOCK-178). Было `agents:
    /// [ApiUser]` — исполнитель теперь роль (AgentProfile), а не учётка.
    var roles: [RoleProfile] = []
    /// Выбранная владельцем роль. `nil` — «Автоматически»: диспетчер сам
    /// подберёт роль (`owner_selected_role` на сервере). Это отдельная ось от
    /// готовности задачи и от фактического `assignee_id`.
    var ownerSelectedRole: String?
    /// Владелец 07.09.2026: «не наблюдаю комментариев с активности» — лента
    /// была только в мёртвом `TaskDetailScreen`/`TaskDetailViewModel` и
    /// потерялась при переезде на эту форму (LOCK-089). Логика (сортировка,
    /// склейка комментариев+событий) — оттуда буквально, вёрстка — своя,
    /// плоская, без аватарок и цветных плашек.
    /// Тот же приём, что у `title`/`taskDescription` выше — блочный Markdown
    /// вместо простой строки (владелец 30.09.2026: «вся карточка как
    /// описание»). `sendComment()` сбрасывает `commentText = ""` после
    /// отправки — сеттер парсит пустую строку обратно в один пустой абзац.
    var commentBlocks: [NoteBlock] = [NoteBlock(kind: .paragraph)]
    var commentText: String {
        get { MarkdownEncoder.encode(commentBlocks) }
        set {
            let parsed = MarkdownParser.parse(newValue)
            commentBlocks = parsed.isEmpty ? [NoteBlock(kind: .paragraph)] : parsed
        }
    }

    var pendingNewStepBlocks: [NoteBlock]?
    var pendingInsertedStepBlocks: [NoteBlock]?
    var pendingInsertAfterStepID: String?
    var loadedTask: ApiTask? { originalTask }

    private var originalTask: ApiTask?
    /// Роль на момент загрузки карточки — чтобы не отправлять
    /// `owner_selected_role` при каждом сохранении, если владелец её не менял.
    /// Отдельно от `originalTask.role`: на живом сервере то поле бывает пустым,
    /// хотя выбранная роль записана.
    private var originalRole: String?

    /// Чем агент занят прямо сейчас — пусто, когда задачу никто не держит.
    var activity: ApiTaskActivity = .idle
    /// Отчёты задачи — «зеркало» документов из папки проекта.
    var reports: [TaskReport] = []


    private var cachedJournalEntries: [TaskJournalEntry] = []
    var journalEntries: [TaskJournalEntry] { cachedJournalEntries }

    /// Чаты, привязанные к этой задаче. Карточка по ним только ПЕРЕХОДИТ в
    /// переписку — свой чат внутри карточки не заводится и не рисуется
    /// (владелец 21.09.2026: «заводить прям чат прямо в карточке не надо,
    /// надо чтобы просто переходил в чат»).
    var taskChats: [ApiTaskChat] { originalTask?.chats ?? [] }

    var isEditing: Bool { taskID != nil }
    /// Для меню «…» (перенесено из `TaskDetailScreen` — открытие задачи
    /// больше не ведёт на отдельный экран-просмотр, она сама и есть форма).
    var executionStatus: TaskExecutionStatus?
    var isLaunchingExecutor = false
    var executionStatusUnavailable = true
    var canLaunchExecutor: Bool {
        !isLaunchingExecutor && !executionStatusUnavailable && (executionStatus?.canLaunch ?? false)
    }
    var canChangeExecutor: Bool { !isLaunchingExecutor && (taskID == nil || (!executionStatusUnavailable && (executionStatus?.canChangeExecutor ?? false))) }
    var canUsePlan: Bool { !isLaunchingExecutor && !executionStatusUnavailable && (executionStatus?.canUsePlan ?? false) }

    func loadExecutionStatus() async {
        guard let taskID else { return }
        do {
            executionStatus = try await apiClient.taskExecutionStatus(id: taskID)
            executionStatusUnavailable = false
        } catch {
            executionStatusUnavailable = true
        }
    }

    var agentState: AgentState? { originalTask?.agentState }
    /// Спек 1.2, 1.2.10 — лесенка модели. На старых задачах (созданных до
    /// спек 1.2) поле отсутствует в ответе — `nil`, UI не рисует индикатор.
    var attemptLadder: ApiAttemptLadder? { originalTask?.attemptLadder }
    var isSaveEnabled: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
            && !aiStructureStatus.isProcessing
    }
    /// «Структурировать с AI» — пункт 2 §5.5: показывается, если в названии/описании уже есть текст.
    var showAiButton: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty || !taskDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `startDictation` — держит флаг для экрана: сфокусировать поле
    /// названия и показать кнопку микрофона (по просьбе оркестратора —
    /// открыть форму «в нужном состоянии»). Само распознавание при тапе по
    /// кнопке живёт в `DictationEngine.shared`, не здесь — эта модель про
    /// то, в каком СОСТОЯНИИ открылась форма, не про звук.
    let startDictation: Bool

    /// `presetDueToday`/`startDictation` — контракт `INTEGRATION.md`
    /// (обновлён оркестратором по ходу этой задачи): `/task/new?due=today`
    /// и `/task/new?dictate=1` из CreateMenu веба.
    init(
        taskID: String?,
        presetDueToday: Bool = false,
        startDictation: Bool = false,
        parentTaskID: String? = nil,
        parentTaskTitle: String? = nil,
        presetProjectID: String? = nil,
        apiClient: APIClient = APIClient()
    ) {
        self.taskID = taskID
        self.apiClient = apiClient
        self.collaborationPlanState = CollaborationPlanState(api: apiClient)
        self.startDictation = startDictation
        self.parentId = parentTaskID
        self.parentTitle = parentTaskTitle
        self.projectId = presetProjectID
        self.attachments = TaskAttachmentsController(apiClient: apiClient, taskId: taskID)
        if presetDueToday, taskID == nil {
            // Срок — полночь дня в зоне задачи (Москва), иначе на телефонах
            // восточнее Москвы дата уезжала на сутки назад.
            dueDate = TaskDay.startOfDay(Date())
        }
    }

    func loadIfNeeded(showLoading: Bool = true) async {
        guard let taskID else { return }
        if showLoading { isLoadingTask = true }
        defer { if showLoading { isLoadingTask = false } }
        do {
            async let status: Void = loadExecutionStatus()
            let task = try await apiClient.task(id: taskID)
            originalTask = task
            cachedJournalEntries = TaskJournalEntry.merged(comments: task.comments ?? [], events: task.events ?? [])
            try adoptTitleDocument(from: task)
            try adoptDescriptionDocument(from: task)
            subtasks = task.subtasks.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            parentId = task.parentId
            childTasks = task.children ?? []
            ancestorTaskIDs.removeAll()
            parentTask = nil
            // Вся цепочка предков пришла с задачей — подниматься по дереву
            // отдельными запросами больше не нужно. Раньше здесь был цикл с
            // запросом на каждого предка: на глубокой карточке это 5–15 запросов
            // подряд, и карточка открывалась долго (владелец 17.10.2026).
            if let parentId = task.parentId {
                for ancestor in task.ancestors ?? [] {
                    ancestorTaskIDs.insert(ancestor.id)
                }
                parentTitle = task.ancestors?.first { $0.id == parentId }?.title
                // Полная задача родителя — один запрос. Раньше на каждый предка
                // шёл отдельный запрос по очереди (5–15 на глубокой карточке),
                // и карточка открывалась долго (владелец 17.10.2026); теперь
                // цепочка приходит с задачей, а родитель тянется один раз.
                parentTask = try? await apiClient.task(id: parentId)
                if parentTitle == nil { parentTitle = parentTask?.title }
            } else {
                parentTask = nil
                parentTitle = nil
            }
            dueDate = task.dueDateAsDate
            startMinutes = task.startTime.flatMap(DateFormats.localTimeComponents).map { $0.hour * 60 + $0.minute }
            durationMin = task.durationMin
            projectId = task.projectId
            priority = TaskPriority(rawValue: task.priority) ?? .low
            selectedLabelIds = Set(task.labels.map(\.id))
            assigneeId = task.assigneeId
            requiresReviewerReview = task.requiresReviewerReview
            runRepeat = task.runRepeat ?? "none"
            repeatUntil = task.repeatUntil.flatMap { Self.dayFormatter.date(from: $0) }
            ownerSelectedRole = task.effectiveRole
            originalRole = task.effectiveRole
            creatorName = task.creatorName
            creatorId = task.creatorId
            attachments = TaskAttachmentsController(apiClient: apiClient, taskId: taskID, existing: task.attachments ?? [])
            await status
        } catch let error as APIError {
            if case .notFound = error { notFound = true } else { loadErrorMessage = Self.message(error) }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    // MARK: - AI-структурирование

    /// Пока локальная модель размышляет, форма не сохраняется: иначе владелец
    /// мог бы закрыть карточку до того, как ответ успел примениться к полям.
    /// Ошибка хранится отдельно от ошибок обычного сохранения, чтобы в карточке
    /// было ясно, какой именно процесс не завершился.
    func structureWithAI() async {
        let source = [title, taskDescription]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !source.isEmpty, !aiStructureStatus.isProcessing else { return }

        aiStructureStatus = .processing
        do {
            let structured = try await apiClient.structureTask(text: source)
            try await apply(structured)
            aiStructureStatus = .completed
        } catch {
            aiStructureStatus = .failed(Self.message(error))
        }
    }

    private func apply(_ structured: APIClient.StructuredTask) async throws {
        let structuredTitle = structured.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !structuredTitle.isEmpty { title = structuredTitle }
        if let description = structured.description { taskDescription = description }
        if let dueDate = TaskDay.date(from: structured.dueDate) { self.dueDate = dueDate }
        if let priority = structured.priority, let value = TaskPriority(rawValue: priority) {
            self.priority = value
        }

        let suggestedSubtasks = structured.subtasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if taskID == nil {
            subtaskDrafts = suggestedSubtasks.map(SubtaskDraft.init(title:))
        } else if let taskID {
            // У существующей карточки уже могут быть выполненные шаги — AI не
            // имеет права их стирать. Добавляем только новые, не дублируя
            // совпадающие по названию.
            var existing = Set(subtasks.map { normalizedSubtaskTitle($0.title) })
            for title in suggestedSubtasks {
                let normalized = normalizedSubtaskTitle(title)
                guard existing.insert(normalized).inserted else { continue }
                let created = try await apiClient.createSubtask(taskId: taskID, title: title)
                subtasks.append(created)
            }
        }
    }

    private func normalizedSubtaskTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Тянут вниз — обновляем и задачу, и строку активности.
    func refresh(activityRevision: Int? = nil) async {
        async let card: Void = reloadTaskQuietly()
        async let activity: Void = loadActivity(revision: activityRevision)
        _ = await (card, activity)
    }

    /// Перезапрос задачи без спиннера и без перетирания того, что владелец
    /// прямо сейчас правит в полях: обновляем только шаги и служебное
    /// состояние, ради которых опрос и заведён.
    private func reloadTaskQuietly() async {
        guard let taskID else { return }
        guard let fresh = try? await apiClient.task(id: taskID) else { return }
        if let old = originalTask { adoptServerChanges(from: old, to: fresh) }
        originalTask = fresh
        cachedJournalEntries = TaskJournalEntry.merged(comments: fresh.comments ?? [], events: fresh.events ?? [])
        await loadExecutionStatus()
        subtasks = fresh.subtasks.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        childTasks = fresh.children ?? []
        await syncLiveActivity(with: fresh)
    }

    /// Поле, которое владелец не трогал (равно прежнему `originalTask`), берём
    /// с сервера. Иначе `saveEdit` сравнил бы старое поле со свежим
    /// `originalTask`, увидел «правку» и автосохранением откатил чужое
    /// изменение — так 16.10.2026 карточку дважды возвращало в старый проект.
    /// Сравнение — то же, что в `saveEdit`, поле за полем.
    func adoptServerChanges(from old: ApiTask, to fresh: ApiTask) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines) == old.title { try? adoptTitleDocument(from: fresh) }
        if descriptionMatches(old.description) { try? adoptDescriptionDocument(from: fresh) }
        if dueDate.map(Self.dueDateString) == old.dueDate { dueDate = fresh.dueDateAsDate }
        let startStr = startMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        if startStr == old.startTime {
            startMinutes = fresh.startTime.flatMap(DateFormats.localTimeComponents).map { $0.hour * 60 + $0.minute }
        }
        if durationMin == old.durationMin { durationMin = fresh.durationMin }
        if projectId == old.projectId { projectId = fresh.projectId }
        if priority.rawValue == old.priority { priority = TaskPriority(rawValue: fresh.priority) ?? .low }
        if selectedLabelIds == Set(old.labels.map(\.id)) { selectedLabelIds = Set(fresh.labels.map(\.id)) }
        if assigneeId == old.assigneeId { assigneeId = fresh.assigneeId }
        if requiresReviewerReview == old.requiresReviewerReview { requiresReviewerReview = fresh.requiresReviewerReview }
        if runRepeat == (old.runRepeat ?? "none") { runRepeat = fresh.runRepeat ?? "none" }
        if repeatUntil.map({ Self.dayFormatter.string(from: $0) }) == old.repeatUntil {
            repeatUntil = fresh.repeatUntil.flatMap { Self.dayFormatter.date(from: $0) }
        }
    }

    /// Островок идёт за карточкой, пока приложение открыто: перезапрос задачи
    /// уже случается по опросу, так что отдельного цикла заводить не нужно.
    ///
    /// Свёрнутое приложение карточку не двигает — фонового выполнения у него
    /// нет. Этим занимается сервер через APNs по токену, который мы отдали
    /// при запуске (`server/src/apns.ts`, ждёт ключей — карточка 75448a64).
    ///
    /// Работа закончилась — островок гасим сами: задача принята или закрыта,
    /// висящая карточка на экране блокировки только мешает.
    private func syncLiveActivity(with task: ApiTask) async {
        guard #available(iOS 16.2, *) else { return }
        if task.status == .completed || task.agentState == nil {
            await LiveActivityService.end(taskID: task.id, api: apiClient)
        } else {
            await LiveActivityService.update(task: task)
        }
    }

    /// Строка активности. Ошибку глотаем: это надстройка над карточкой,
    /// ронять из-за неё экран нельзя.
    /// Отчёты задачи. Загружаются один раз с карточкой: их немного, и они не
    /// живые (в отличие от активности), обновлять по таймеру незачем.
    func loadReports() async {
        guard let taskID else { return }
        do {
            reports = try await apiClient.taskReports(taskId: taskID)
        } catch {
            reports = []
        }
    }

    /// Несколько наблюдателей разделяют запрос. Новая ревизия во время
    /// загрузки требует завершающего запроса, чтобы не потерять событие.
    func loadActivity(revision: Int? = nil) async {
        guard let taskID else { return }
        if let revision { activityRequestedRevision = max(activityRequestedRevision ?? revision, revision) }
        if let activityLoad {
            await activityLoad.value
            return
        }
        let load = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activityLoad = nil }
            repeat {
                let requestedRevision = self.activityRequestedRevision
                do {
                    let fresh = try await self.apiClient.taskActivity(taskId: taskID)
                    guard !Task.isCancelled else { return }
                    if requestedRevision != self.activityRequestedRevision { continue }
                    self.activity = fresh
                } catch {
                    guard !Task.isCancelled else { return }
                    if requestedRevision != self.activityRequestedRevision { continue }
                    self.activity = .idle
                }
                return
            } while !Task.isCancelled
        }
        activityLoad = load
        await load.value
    }

    /// Исполнители — роли (`GET /api/roles`), не учётки. Ошибка — та же общая
    /// формулировка справочников, что и раньше.
    func loadRoles() async {
        do {
            roles = try await apiClient.rolesList()
        } catch {
            directoriesErrorMessage = "Не удалось загрузить проекты, метки или агентов. Проверьте соединение."
        }
    }

    // MARK: - Лента: комментарии — перенесено буквально из
    // `TaskDetailViewModel.sendComment` (файлы к комментарию не переносил —
    // отдельный кусок с `fileImporter`, не входит в этот проход).
    func sendComment() async {
        guard let taskID else { return }
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            _ = try await apiClient.createComment(taskId: taskID, text: text, attachmentIds: [])
            commentText = ""
            await loadIfNeeded()
        } catch {
            // Формулировка дословно из спеки §19.2.
            saveErrorMessage = "Не удалось отправить — попробуйте ещё раз"
        }
    }

    // MARK: - Подзадачи (просмотр — карточки-агенты) — перенесено буквально
    // из TaskDetailViewModel, для `SubtaskFeedView` в режиме чтения.

    func toggleSubtaskDone(_ subtask: ApiSubtask) async {
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["done": .bool(!subtask.done)])
            await loadIfNeeded()
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    func acceptSubtask(_ subtask: ApiSubtask) async {
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["done": .bool(true)])
            await loadIfNeeded()
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    /// Ответ на заблокированный шаг: снимает блокировку + пишет комментарий
    /// к задаче. Аналог SubtaskFeed.tsx onComment. Раньше тут был
    /// patchSubtask({result: text}) — запись попадала только в result шага,
    /// блокировка оставалась, в ленте задачи ничего не появлялось.
    func replyToSubtask(_ subtask: ApiSubtask, text: String) async {
        guard let taskId = subtask.taskId else { return }
        do {
            _ = try await apiClient.setSubtaskWork(id: subtask.id, fields: ["state": .null])
            let commentText = "По шагу «\(subtask.title)»: \(text)"
            _ = try await apiClient.createComment(taskId: taskId, text: commentText)
            await loadIfNeeded()
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    // MARK: - Действия владельца над агентской работой (перенесено из
    // TaskDetailViewModel.performOwnerAction — §19.2 AgentOwnerActions,
    // логика не менялась, только источник taskID/reload).

    /// Сервер возвращает точную причину отказа (`{error: ...}`). Не прячем её
    /// за общей фразой: при возврате из review владелец должен понимать,
    /// что именно нужно исправить — например, добавить обязательный
    /// комментарий.
    nonisolated static func ownerActionErrorMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Не удалось изменить состояние задачи"
    }

    /// Текст из alert нужно забрать до закрытия alert: `Task {}` стартует
    /// асинхронно, а сброс `@State` сразу после него иначе стирает комментарий
    /// раньше, чем он попадёт в запрос review → in_progress.
    nonisolated static func ownerActionCommentForSubmission(_ text: String) -> String? {
        let comment = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? nil : comment
    }

    /// `taskStore` — тот же общий кэш списков, что и у `save(taskStore:)`.
    /// Своей карточки мало: «Работа агентов» и плитки «Обзора» рисуют секции
    /// из стора, а он о владельческом действии не знает. Владелец 10.09.2026
    /// открыл задачу из «Обзора» → «В работе», принял её — «что-то моргнуло
    /// и на этом всё»: на сервере задача закрылась (проверено по логу — 200
    /// на обоих запросах), а строка осталась висеть в списке до перезахода.
    func performOwnerAction(_ kind: AgentOwnerActionKind, comment: String?, taskStore: TaskStore) async {
        guard let taskID else { return }
        do {
            switch kind {
            case .acceptReview:
                try await apiClient.approveCurrentTaskVersion(taskID: taskID)
                _ = try await apiClient.setTaskAgentState(id: taskID, state: nil, comment: comment)
                _ = try await apiClient.patchTask(id: taskID, fields: ["status": .string("completed")])
            case .acceptAndClose:
                // Сервер принимает `completed` только после одобрения
                // актуальной версии результата. Для обычной активной или
                // blocked-задачи отдельного review нет; в состоянии review
                // сначала фиксируем verdict по текущей версии.
                if agentState == .review {
                    try await apiClient.approveCurrentTaskVersion(taskID: taskID)
                }
                _ = try await apiClient.setTaskAgentState(id: taskID, state: nil, comment: comment)
                _ = try await apiClient.patchTask(id: taskID, fields: ["status": .string("completed")])
            case .returnToWorkFromReview:
                _ = try await apiClient.setTaskAgentState(id: taskID, state: .inProgress, comment: comment)
            case .replyAndReturnFromBlocked:
                // `blocked → in_progress` сервер пропускает только
                // исполнителю: владелец получал 400 «invalid transition»,
                // и комментарий из того же запроса пропадал (22.09.2026).
                // Как в вебе (`TaskJournal.tsx`, `handleAnswer`): СНАЧАЛА
                // снять блокировку, ПОТОМ комментарий — будильник
                // просыпается по комментарию и сразу перечитывает задачу;
                // застанет её ещё blocked — пройдёт мимо.
                _ = try await apiClient.setTaskAgentState(id: taskID, state: nil)
                if let comment {
                    _ = try await apiClient.createComment(taskId: taskID, text: comment)
                }
            case .returnToWorkFromInProgress:
                _ = try await apiClient.setTaskAgentState(id: taskID, state: nil, comment: comment)
            }
            await loadIfNeeded()
            // Полный рефетч, а не точечная замена: приёмка меняет у задачи и
            // `status`, и `agent_state`, а «Принять и закрыть» на родителе
            // задевает ещё и дочерние — что именно пересчитал сервер, знает
            // только он. Тихо, без спиннера: список уже на экране.
            await taskStore.load(silent: true)
        } catch {
            saveErrorMessage = Self.ownerActionErrorMessage(error)
        }
    }

    /// Ручной разовый запуск агента на этой карточке — исполнителя или
    /// верификатора. Автоматику не включает: один заход по команде владельца.
    /// `true` — сервер принял запуск.
    func runAgent(mode: String) async -> Bool {
        guard let taskID else { return false }
        if mode == "executor" {
            guard canLaunchExecutor else { return false }
            isLaunchingExecutor = true
        }
        defer { if mode == "executor" { isLaunchingExecutor = false } }
        do {
            try await apiClient.runTask(id: taskID, mode: mode)
            await loadExecutionStatus()
            await reloadTaskQuietly()
            assigneeId = originalTask?.assigneeId
            return true
        } catch {
            saveErrorMessage = Self.ownerActionErrorMessage(error)
            await loadExecutionStatus()
            return false
        }
    }

    /// Серия повтора завершена (воркер ждёт «Продлить на год»).
    var seriesEnded: Bool { (originalTask?.recurrenceSpawned ?? 0) == 1 }

    /// Продлить серию повтора на следующий календарный год (владелец).
    func extendRepeat() async -> Bool {
        guard let taskID else { return false }
        do {
            try await apiClient.extendRepeat(id: taskID)
            await loadIfNeeded()
            return true
        } catch {
            saveErrorMessage = Self.ownerActionErrorMessage(error)
            return false
        }
    }

    // MARK: - Подзадачи (edit) — точечные вызовы, отдельные от общего PATCH задачи.

    /// «Запустить» (23.09.2026): задача верхнего уровня — через сервер, тем же
    /// путём, что кнопка на карточке Помощника владельца: дерево целиком, с очередью,
    /// личные дела не трогаются. Дочерняя — флаг одной этой карточке.
    func startTask(taskStore: TaskStore) async {
        guard let task = originalTask else { return }
        do {
            if task.parentId == nil || !childTasks.isEmpty {
                try await apiClient.startDraft(taskID: task.id)
            } else {
                _ = try await apiClient.patchTask(id: task.id, fields: ["ready_for_pickup": .bool(true)])
            }
            await loadIfNeeded()
            await taskStore.load(silent: true)
        } catch {
            saveErrorMessage = (error as? APIError)?.errorDescription ?? "Не удалось запустить задачу"
        }
    }

    /// Поднять/снять флаг готовности задачи к самозахвату (миграция 026,
    /// карточка 04426aeb). Сервер примет PATCH только от владельца
    /// (`isOwner` на клиенте гейт уже отрезал), иначе 403. Здесь мы
    /// просто шлём — повторный заход не нужен, потому что условие
    /// проверяется до показа кнопки.
    func toggleReadyFlag(taskStore: TaskStore) async {
        guard let task = originalTask else { return }
        let next = !task.readyForPickup
        do {
            _ = try await apiClient.patchTask(id: task.id, fields: [
                "ready_for_pickup": .bool(next),
            ])

            // Родительская карточка — это единая постановка работы. Если
            // владелец открыл её для самозахвата, ни одна дочерняя карточка
            // не должна остаться закрытой для исполнителя (и наоборот при
            // снятии флага). Серверного каскада у PATCH задачи нет, поэтому
            // синхронизируем все дочерние задачи явно.
            for child in childTasks where child.readyForPickup != next {
                _ = try await apiClient.patchTask(id: child.id, fields: [
                    "ready_for_pickup": .bool(next),
                ])
            }

            await loadIfNeeded()
            // Тихо обновить список, чтобы плашки родителя и детей на доске
            // тоже переключились.
            await taskStore.load(silent: true)
        } catch {
            saveErrorMessage = "Не удалось изменить готовность задачи"
        }
    }

    /// Удобное отражение `originalTask.readyForPickup` для UI (кнопка
    /// в `editingToolbarItems`). Дефолт `false`: пока задача не
    /// загружена, кнопка показывает «Готово к работе» — достоверно
    /// неверно, но и экран ещё нельзя трогать.
    var readyForPickup: Bool {
        originalTask?.readyForPickup ?? false
    }

    /// «Нужно глубокое исследование» (миграция 052 сервера New-Todoist) —
    /// обычное поле карточки. Тумблер в меню «…» владельца; каскада на
    /// дочерние, как у флага готовности, здесь нет: это отметка одной задачи.
    func toggleNeedsResearch(taskStore: TaskStore) async {
        guard let task = originalTask else { return }
        let next = !task.needsResearch
        do {
            _ = try await apiClient.patchTask(id: task.id, fields: [
                "needs_research": .bool(next),
            ])
            await loadIfNeeded()
            await taskStore.load(silent: true)
        } catch {
            saveErrorMessage = "Не удалось изменить отметку исследования"
        }
    }

    var needsResearch: Bool {
        originalTask?.needsResearch ?? false
    }

    /// Запустить серверный конвейер глубокого исследования. Если флага нет —
    /// сначала поднимаем его (конвейер пускает только помеченные задачи),
    /// затем дёргаем `POST /research`. Возвращает `true`, когда запуск принят:
    /// по нему экран показывает подтверждение.
    func startResearch() async -> Bool {
        guard let task = originalTask else { return false }
        do {
            if !task.needsResearch {
                _ = try await apiClient.patchTask(id: task.id, fields: [
                    "needs_research": .bool(true),
                ])
                await loadIfNeeded()
            }
            try await apiClient.startResearch(id: task.id)
            return true
        } catch {
            saveErrorMessage = "Не удалось запустить исследование"
            return false
        }
    }

    var pinned: Bool { originalTask?.pinned ?? false }

    /// Закрепить/открепить задачу. Раньше это делала скрепка в каждой строке
    /// списка проекта; владелец 11.09.2026 убрал её из строк и оставил
    /// действие здесь, в меню «…».
    func togglePinned(taskStore: TaskStore) async {
        guard let task = originalTask else { return }
        do {
            _ = try await apiClient.patchTask(id: task.id, fields: ["pinned": .bool(!task.pinned)])
            await loadIfNeeded()
            // Порядок в списках зависит от закрепления — обновляем и их.
            await taskStore.load(silent: true)
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    /// ⚠️ Отказ сервера здесь ОБЯЗАН быть виден. Раньше стоял `try?`, и
    /// отклонённое добавление выглядело как «нажал — ничего не произошло»:
    /// 11.09.2026 сервер отвечал на этот вызов 404 (чужая карточка), а
    /// экран молчал, и владелец решил, что кнопка не реализована.
    /// `afterId` — вставить новую подзадачу сразу после этой, а не в конец.
    func addSubtask(_ title: String, afterId: String? = nil) async {
        guard let taskID else { return }
        do {
            let created = try await apiClient.createSubtask(taskId: taskID, title: title, afterId: afterId)
            if let afterId, let index = subtasks.firstIndex(where: { $0.id == afterId }) {
                subtasks.insert(created, at: index + 1)
            } else {
                subtasks.append(created)
            }
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    @discardableResult
    func renameSubtask(_ subtask: ApiSubtask, to newTitle: String) async -> Bool {
        guard let index = subtasks.firstIndex(where: { $0.id == subtask.id }) else { return false }
        let snapshot = subtasks[index]
        subtasks[index] = ApiSubtask(
            id: subtask.id, taskId: subtask.taskId, title: newTitle, done: subtask.done, position: subtask.position,
            agentState: subtask.agentState, agentId: subtask.agentId, agentHeartbeatAt: subtask.agentHeartbeatAt,
            result: subtask.result, agentSessionId: subtask.agentSessionId, state: subtask.state
        )
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["title": .string(newTitle)])
            return true
        } catch {
            // Откат молча — это «текст сам вернулся к старому», без объяснений.
            subtasks[index] = snapshot
            saveErrorMessage = Self.message(error)
            return false
        }
    }

    func deleteSubtask(_ subtask: ApiSubtask) async {
        let snapshot = subtasks
        subtasks.removeAll { $0.id == subtask.id }
        do {
            try await apiClient.deleteSubtask(id: subtask.id)
        } catch {
            subtasks = snapshot
            saveErrorMessage = Self.message(error)
        }
    }

    func reorderSubtasks(_ newOrder: [ApiSubtask]) async {
        subtasks = newOrder
        for (index, subtask) in newOrder.enumerated() where subtask.position != index {
            _ = try? await apiClient.patchSubtask(id: subtask.id, fields: ["position": .number(Double(index))])
        }
    }

    // MARK: - Связанные задачи (`tasks.parent_id`)

    /// Вывести задачу в островок (Dynamic Island).
    ///
    /// До 10.09.2026 кнопка показывала только тост: виджет жил в Capacitor-
    /// обёртке, а в нативном клиенте таргета расширения не было вовсе.
    /// Владелец нажал, свернул приложение и увидел пустоту.
    ///
    /// Возвращает текст для тоста — чтобы экран не решал, что случилось.
    @available(iOS 16.2, *)
    func outputToDynamicIsland() async -> String {
        guard let task = originalTask else {
            return "Сначала сохраните задачу"
        }
        guard LiveActivityService.isAvailable else {
            // Живые активности выключены в настройках телефона — честно
            // говорим об этом, а не рапортуем об успехе.
            return "Включите «Live Activities» в настройках телефона"
        }
        do {
            try await LiveActivityService.start(for: task, api: apiClient)
            return "Задача выведена в Dynamic Island"
        } catch {
            return "Не удалось вывести в Dynamic Island"
        }
    }

    func linkExistingTask(_ task: ApiTask) async -> Bool {
        guard let taskID else {
            // У новой карточки связь не надо откладывать отдельным запросом:
            // её будущий родитель уже известен и уйдёт первым POST /tasks как
            // `parent_id`. Так черновик сразу показывает выбранную связь.
            parentId = task.id
            parentTitle = task.title
            parentTask = task
            return true
        }
        do {
            _ = try await apiClient.patchTask(
                id: task.id,
                fields: ["parent_id": .string(taskID)]
            )
            await loadIfNeeded()
            return true
        } catch {
            saveErrorMessage = Self.message(error)
            return false
        }
    }

    func unlinkChildTask(_ task: ApiTask) async {
        do {
            _ = try await apiClient.patchTask(id: task.id, fields: ["parent_id": .null])
            await loadIfNeeded()
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    /// Выбрать родителя для этой карточки (владелец 16.10.2026: у уже
    /// созданной карточки родителя выбрать было нельзя — только у новой).
    func setParent(_ task: ApiTask) async -> Bool {
        guard let taskID else {
            parentId = task.id
            parentTitle = task.title
            parentTask = task
            return true
        }
        do {
            _ = try await apiClient.patchTask(id: taskID, fields: ["parent_id": .string(task.id)])
            await loadIfNeeded()
            return true
        } catch {
            saveErrorMessage = Self.message(error)
            return false
        }
    }

    func unlinkFromParent() async {
        guard parentId != nil else { return }
        guard let taskID else {
            parentId = nil
            parentTitle = nil
            parentTask = nil
            return
        }
        do {
            _ = try await apiClient.patchTask(id: taskID, fields: ["parent_id": .null])
            await loadIfNeeded()
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    // MARK: - Сохранение

    /// `true` — сохранено успешно, экран может закрыться.
    func save(taskStore: TaskStore) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        do {
            if let taskID {
                try await saveEdit(taskID: taskID, trimmedTitle: trimmedTitle, taskStore: taskStore)
            } else {
                try await saveCreate(trimmedTitle: trimmedTitle, taskStore: taskStore)
            }
            if let taskID {
                try await flushDeferredComment(taskID: taskID)
            }
            return true
        } catch {
            saveErrorMessage = Self.message(error)
            return false
        }
    }

    /// Срок → `YYYY-MM-DD` по зоне задачи (Москва). Пикер отдаёт дату в зоне
    /// устройства, поэтому она сперва переводится в полночь выбранного дня в
    /// зоне задачи (`dueDateFromPicker`) — тогда на сервер уходит ровно тот
    /// день, который показал пикер.
    nonisolated static func dueDateString(_ date: Date) -> String {
        TaskDay.string(from: date)
    }

    /// Дата, выбранная в системном пикере (пикер отдаёт её в зоне устройства)
    /// → срок: полночь того же календарного дня в зоне задачи.
    nonisolated static func dueDateFromPicker(
        _ pickerDate: Date,
        deviceTimeZone: TimeZone = .autoupdatingCurrent
    ) -> Date {
        TaskDay.instant(forPickerDay: pickerDate, deviceTimeZone: deviceTimeZone)
    }

    /// Срок (полночь дня в зоне задачи) → дата для пикера: тот же
    /// календарный день, собранный в зоне устройства, — иначе пикер на
    /// телефонах западнее Москвы показывал бы соседний день.
    nonisolated static func pickerDateForDisplay(
        _ dueDate: Date,
        deviceTimeZone: TimeZone = .autoupdatingCurrent
    ) -> Date {
        TaskDay.pickerDate(forTaskDay: dueDate, deviceTimeZone: deviceTimeZone)
    }

    private func saveEdit(taskID: String, trimmedTitle: String, taskStore: TaskStore) async throws {
        guard let originalTask else { throw APIError.invalidResponse }
        var fields: [String: JSONValue] = [:]
        if trimmedTitle != originalTask.title { fields["title"] = .string(trimmedTitle) }
        let desc = taskDescription.isEmpty ? nil : taskDescription
        if !descriptionMatches(originalTask.description) { fields["description"] = desc.map { JSONValue.string($0) } ?? .null }
        let dueStr = dueDate.map(Self.dueDateString)
        if dueStr != originalTask.dueDate { fields["due_date"] = dueStr.map { JSONValue.string($0) } ?? .null }
        let startStr = startMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        if startStr != originalTask.startTime { fields["start_time"] = startStr.map { JSONValue.string($0) } ?? .null }
        if durationMin != originalTask.durationMin { fields["duration_min"] = durationMin.map { JSONValue.number(Double($0)) } ?? .null }
        if projectId != originalTask.projectId { fields["project_id"] = projectId.map { JSONValue.string($0) } ?? .null }
        if priority.rawValue != originalTask.priority { fields["priority"] = .number(Double(priority.rawValue)) }
        if selectedLabelIds != Set(originalTask.labels.map(\.id)) {
            fields["label_ids"] = .array(selectedLabelIds.sorted().map { .string($0) })
        }
        if assigneeId != originalTask.assigneeId { fields["assignee_id"] = assigneeId.map { JSONValue.string($0) } ?? .null }
        // Роль-исполнитель, выбранная владельцем (LOCK-178). Пусто — снять
        // выбор и вернуть задачу диспетчеру («Автоматически»). Сравниваем со
        // своей запомненной ролью, а не с `originalTask.role`: то поле на
        // живом сервере может быть пустым при записанной роли.
        if ownerSelectedRole != originalRole {
            fields["owner_selected_role"] = ownerSelectedRole.map { JSONValue.string($0) } ?? .null
        }
        if requiresReviewerReview != originalTask.requiresReviewerReview {
            fields["requires_reviewer_review"] = .bool(requiresReviewerReview)
        }
        if runRepeat != (originalTask.runRepeat ?? "none") {
            fields["run_repeat"] = .string(runRepeat)
        }
        let untilStr = repeatUntil.map { Self.dayFormatter.string(from: $0) }
        if untilStr != originalTask.repeatUntil {
            fields["repeat_until"] = untilStr.map { JSONValue.string($0) } ?? .null
        }

        guard !fields.isEmpty else { return }
        let updated = try await apiClient.patchTask(id: taskID, fields: fields)
        self.originalTask = updated
        taskStore.apply(.taskUpdated(updated))
        if ownerSelectedRole != originalRole { originalRole = ownerSelectedRole }
    }

    private func saveCreate(trimmedTitle: String, taskStore: TaskStore) async throws {
        let payload = APIClient.NewTaskRequest(
            title: trimmedTitle,
            description: taskDescription.isEmpty ? nil : taskDescription,
            dueDate: dueDate.map(Self.dueDateString),
            startTime: startMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) },
            durationMin: durationMin,
            projectId: projectId,
            assigneeId: assigneeId,
            priority: priority.rawValue,
            parentId: parentId,
            labelIds: selectedLabelIds.isEmpty ? nil : Array(selectedLabelIds),
            subtasks: subtaskDrafts.isEmpty ? nil : subtaskDrafts.map(\.title),
            // Повтор при СОЗДАНИИ раньше молча терялся: в теле создания не
            // было полей `run_repeat`/`repeat_until`, и выбранный в форме
            // повтор до сервера не доходил (правка списка их шла).
            runRepeat: runRepeat == "none" ? nil : runRepeat,
            repeatUntil: repeatUntil.map { Self.dayFormatter.string(from: $0) },
            // Флаг не шлём: маршрут новой карточки решает общая настройка
            // владельца «Сначала проверка Reviewer» (Обзор → Система).
            requiresReviewerReview: nil
        )
        guard let created = await taskStore.create(payload) else {
            throw APIError.server(status: 0, message: "Не удалось сохранить задачу")
        }
        taskID = created.id
        originalTask = created
        // Рутина создаётся после карточки: её шаблон — эта задача. Ошибка
        // создания рутины не отменяет созданную задачу — владельцу показываем
        // сообщение, карточка остаётся на месте.
        if routineEnabled {
            await createRoutineForTask(trimmedTitle: trimmedTitle)
        }
        // Файлы, накопленные локально до создания задачи — заливаем теперь,
        // когда id наконец известен (см. `AttachmentsFieldView.swift`).
        await attachments.flushPending(taskId: created.id)
    }

    /// Повтор карточки → правило рутины. В форме то же поле «повтор», поэтому
    /// и правило рутины берётся из него (спека, уточнение 22.10.2026).
    nonisolated static func routineRuleKind(fromRepeat value: String) -> String {
        switch value {
        case "weekdays": return "weekdays"
        case "weekly": return "weekly"
        case "monthly": return "monthly"
        default: return "daily"
        }
    }

    /// День недели или число месяца для рутины из формы задачи — из срока
    /// задачи: «повтор» у карточки значит «в этот день недели», и рутина
    /// должна срабатывать в тот же день, а не в день создания.
    nonisolated static func routineRuleExpr(ruleKind: String, dueDate: Date?) -> String? {
        guard let dueDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TaskDateText.moscow
        switch ruleKind {
        case "weekly":
            let sundayFirst = calendar.component(.weekday, from: dueDate)
            let iso = sundayFirst == 1 ? 7 : sundayFirst - 1
            return RoutineFormat.weekdayExpr(iso)
        case "monthly":
            return RoutineFormat.monthDayExpr(calendar.component(.day, from: dueDate))
        default:
            return nil
        }
    }

    /// Рутина из формы задачи: та же карточка, но создаётся снова и снова.
    private func createRoutineForTask(trimmedTitle: String) async {
        let payload = ApiSchedulePayload(
            title: trimmedTitle,
            description: taskDescription.isEmpty ? nil : taskDescription,
            projectId: projectId,
            assigneeId: ownerSelectedRole ?? assigneeId,
            priority: priority.rawValue,
            durationMin: durationMin
        )
        let ruleKind = Self.routineRuleKind(fromRepeat: runRepeat)
        let request = ApiScheduleCreateRequest(
            title: trimmedTitle,
            ruleKind: ruleKind,
            ruleExpr: Self.routineRuleExpr(ruleKind: ruleKind, dueDate: dueDate),
            timeLocal: RoutineFormat.timeLocalText(startMinutes ?? 9 * 60),
            timezone: RoutineFormat.localTimezone,
            catchUp: true,
            overlapPolicy: "skip",
            taskPayload: payload
        )
        do {
            _ = try await apiClient.createSchedule(request)
            routineNotice = "Рутина создана — задача будет создаваться снова по расписанию"
        } catch {
            routineNotice = "Задача создана, но рутину создать не удалось: \(Self.message(error))"
        }
    }

    private func flushDeferredComment(taskID: String) async throws {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        _ = try await apiClient.createComment(taskId: taskID, text: text, attachmentIds: [])
        commentText = ""
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

/// Начальная загрузка уже получила снимок карточки. Перечитываем его только
/// после изменения релевантной ревизии или возвращения из фона.
struct TaskCardRefreshState {
    struct Snapshot {
        var staleRevision: Int
        var taskRevisions: [String: Int]
        var activityRevision: Int
    }
    private var cardSnapshot: Snapshot?
    private var activityRevision: Int?
    private var cardResumed = false
    private var activityResumed = false

    mutating func begin(_ snapshot: Snapshot) {
        cardSnapshot = snapshot
        activityRevision = snapshot.activityRevision
        cardResumed = false
        activityResumed = false
    }

    mutating func cardNeedsRefresh(_ snapshot: Snapshot, taskIDs: Set<String>, ready: Bool, active: Bool) -> Bool {
        guard active else {
            if ready { cardResumed = true }
            return false
        }
        guard ready, let previous = cardSnapshot else { return false }
        let changed = cardResumed || snapshot.staleRevision != previous.staleRevision
            || taskIDs.contains { snapshot.taskRevisions[$0, default: 0] != previous.taskRevisions[$0, default: 0] }
        cardSnapshot = snapshot
        cardResumed = false
        return changed
    }

    mutating func activityNeedsRefresh(_ snapshot: Snapshot, ready: Bool, active: Bool) -> Bool {
        guard active else {
            if ready { activityResumed = true }
            return false
        }
        guard ready, let previous = activityRevision else { return false }
        let changed = activityResumed || snapshot.activityRevision != previous
        activityRevision = snapshot.activityRevision
        activityResumed = false
        return changed
    }
}
