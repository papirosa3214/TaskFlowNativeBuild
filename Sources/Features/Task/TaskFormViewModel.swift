import Foundation
import Observation

// Вью-модель формы задачи — spec/SCREENS-1.md §5.5. Своя `APIClient()`, а не
// из окружения: `TaskFlowApp` кладёт в `.environment` только сторы, сам
// клиент нигде не раздаётся (см. отчёт — предложение добавить его в
// environment для будущих экранов).
@MainActor
@Observable
final class TaskFormViewModel {
    let taskID: String?
    private let apiClient = APIClient()

    var title = ""
    var taskDescription = ""
    var subtaskDrafts: [SubtaskDraft] = [] // режим create
    var subtasks: [ApiSubtask] = []        // режим edit — с сервера
    var dueDate: Date?
    var startMinutes: Int?
    var durationMin: Int?
    var projectId: String?
    var priority: TaskPriority = .low
    var selectedLabelIds: Set<String> = []
    var assigneeId: String?
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
    var directoriesErrorMessage: String?
    var agents: [ApiUser] = []
    /// Владелец 07.09.2026: «не наблюдаю комментариев с активности» — лента
    /// была только в мёртвом `TaskDetailScreen`/`TaskDetailViewModel` и
    /// потерялась при переезде на эту форму (LOCK-089). Логика (сортировка,
    /// склейка комментариев+событий) — оттуда буквально, вёрстка — своя,
    /// плоская, без аватарок и цветных плашек.
    var commentText = ""

    private var originalTask: ApiTask?

    /// Чем агент занят прямо сейчас — пусто, когда задачу никто не держит.
    var activity: ApiTaskActivity = .idle

    private var pollTask: Task<Void, Never>?

    var journalEntries: [TaskJournalEntry] {
        TaskJournalEntry.merged(comments: originalTask?.comments ?? [], events: originalTask?.events ?? [])
    }

    var isEditing: Bool { taskID != nil }
    /// Для меню «…» (перенесено из `TaskDetailScreen` — открытие задачи
    /// больше не ведёт на отдельный экран-просмотр, она сама и есть форма).
    var agentState: AgentState? { originalTask?.agentState }
    var isSaveEnabled: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }
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
        presetProjectID: String? = nil
    ) {
        self.taskID = taskID
        self.startDictation = startDictation
        self.parentId = parentTaskID
        self.parentTitle = parentTaskTitle
        self.projectId = presetProjectID
        self.attachments = TaskAttachmentsController(apiClient: APIClient(), taskId: taskID)
        if presetDueToday, taskID == nil {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TaskDateText.moscow
            dueDate = cal.startOfDay(for: Date())
        }
    }

    func loadIfNeeded() async {
        guard let taskID else { return }
        isLoadingTask = true
        defer { isLoadingTask = false }
        do {
            let task = try await apiClient.task(id: taskID)
            originalTask = task
            title = task.title
            taskDescription = task.description ?? ""
            subtasks = task.subtasks.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            parentId = task.parentId
            childTasks = task.children ?? []
            ancestorTaskIDs.removeAll()
            parentTask = nil
            if let parentId = task.parentId {
                var nextAncestorID: String? = parentId
                while let ancestorID = nextAncestorID, !ancestorTaskIDs.contains(ancestorID) {
                    ancestorTaskIDs.insert(ancestorID)
                    guard let ancestor = try? await apiClient.task(id: ancestorID) else { break }
                    if ancestorID == parentId { parentTask = ancestor }
                    nextAncestorID = ancestor.parentId
                }
                parentTitle = parentTask?.title
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
            attachments = TaskAttachmentsController(apiClient: apiClient, taskId: taskID, existing: task.attachments ?? [])
        } catch let error as APIError {
            if case .notFound = error { notFound = true } else { loadErrorMessage = Self.message(error) }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Живое обновление, пока карточка открыта

    /// Открытая карточка сама себя обновляет — на сокет этот экран не
    /// подписан, а `TaskStore` держит только список задач, без шагов и ленты.
    /// Без опроса состояние шага замирало бы в том виде, в каком было при
    /// открытии: агент работает, а крутилка у шага не появляется вовсе.
    /// Владелец 09.09.2026: «в вебе крутилка есть, в приложении нет». В вебе
    /// ровно тот же приём — `src/screens/TaskDetailScreen.tsx` опрашивает
    /// задачу, пока агент её держит.
    ///
    /// Каденс: активность — 15 с (этим же запросом сервер узнаёт, что на
    /// карточку смотрят, и только тогда зовёт локальную модель за пересказом),
    /// задача — 30 с, как в вебе.
    func startPolling() {
        guard taskID != nil, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                await self.loadActivity()
                tick += 1
                if tick % 2 == 0 { await self.reloadTaskQuietly() }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Тянут вниз — обновляем и задачу, и строку активности.
    func refresh() async {
        await reloadTaskQuietly()
        await loadActivity()
    }

    /// Перезапрос задачи без спиннера и без перетирания того, что владелец
    /// прямо сейчас правит в полях: обновляем только шаги и служебное
    /// состояние, ради которых опрос и заведён.
    private func reloadTaskQuietly() async {
        guard let taskID else { return }
        guard let fresh = try? await apiClient.task(id: taskID) else { return }
        originalTask = fresh
        subtasks = fresh.subtasks.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        childTasks = fresh.children ?? []
        await syncLiveActivity(with: fresh)
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
    func loadActivity() async {
        guard let taskID else {
            NSLog("[TFACT] taskID пуст")
            return
        }
        guard originalTask?.agentState == .inProgress,
              originalTask?.agentStale != true else {
            activity = .idle
            NSLog("[TFACT] пропуск: state=\(String(describing: originalTask?.agentState)) stale=\(String(describing: originalTask?.agentStale)) original=\(originalTask == nil ? "nil" : "есть")")
            return
        }
        do {
            let fresh = try await apiClient.taskActivity(taskId: taskID)
            activity = fresh
            NSLog("[TFACT] ok text=\(fresh.text ?? "nil") actions=\(fresh.actions.count) active=\(fresh.isActive)")
        } catch {
            activity = .idle
            NSLog("[TFACT] ошибка: \(error)")
        }
    }

    func loadAgents() async {
        do {
            agents = try await apiClient.agents()
        } catch {
            // Формулировка дословно из спеки — общая ошибка справочников
            // (проекты/метки грузит `ProjectStore`/`LabelStore` из окружения,
            // сюда добавляются только агенты, которых стор не хранит).
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

    func replyToSubtask(_ subtask: ApiSubtask, text: String) async {
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["result": .string(text)])
            await loadIfNeeded()
        } catch {
            saveErrorMessage = Self.message(error)
        }
    }

    // MARK: - Действия владельца над агентской работой (перенесено из
    // TaskDetailViewModel.performOwnerAction — §19.2 AgentOwnerActions,
    // логика не менялась, только источник taskID/reload).

    func performOwnerAction(_ kind: AgentOwnerActionKind, comment: String?) async {
        guard let taskID else { return }
        do {
            switch kind {
            case .acceptReview, .acceptAndClose:
                _ = try await apiClient.setTaskAgentState(id: taskID, state: nil, comment: comment)
                _ = try await apiClient.patchTask(id: taskID, fields: ["status": .string("completed")])
            case .returnToWorkFromReview, .replyAndReturnFromBlocked:
                _ = try await apiClient.setTaskAgentState(id: taskID, state: .inProgress, comment: comment)
            case .returnToWorkFromInProgress:
                _ = try await apiClient.setTaskAgentState(id: taskID, state: nil, comment: comment)
            }
            await loadIfNeeded()
        } catch {
            // Формулировка дословно из спеки §19.2 (как было в TaskDetailViewModel).
            saveErrorMessage = "Не удалось изменить состояние задачи"
        }
    }

    // MARK: - Подзадачи (edit) — точечные вызовы, отдельные от общего PATCH задачи.

    func addSubtask(_ title: String) async {
        guard let taskID else { return }
        if let created = try? await apiClient.createSubtask(taskId: taskID, title: title) {
            subtasks.append(created)
        }
    }

    func renameSubtask(_ subtask: ApiSubtask, to newTitle: String) async {
        guard let index = subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
        let snapshot = subtasks[index]
        subtasks[index] = ApiSubtask(
            id: subtask.id, taskId: subtask.taskId, title: newTitle, done: subtask.done, position: subtask.position,
            agentState: subtask.agentState, agentId: subtask.agentId, agentHeartbeatAt: subtask.agentHeartbeatAt,
            result: subtask.result, agentSessionId: subtask.agentSessionId, state: subtask.state
        )
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["title": .string(newTitle)])
        } catch {
            subtasks[index] = snapshot
        }
    }

    func deleteSubtask(_ subtask: ApiSubtask) async {
        let snapshot = subtasks
        subtasks.removeAll { $0.id == subtask.id }
        do {
            try await apiClient.deleteSubtask(id: subtask.id)
        } catch {
            subtasks = snapshot
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
        guard let taskID else { return false }
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

    func unlinkFromParent() async {
        guard let taskID, parentId != nil else { return }
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
            return true
        } catch {
            saveErrorMessage = Self.message(error)
            return false
        }
    }

    private func saveEdit(taskID: String, trimmedTitle: String, taskStore: TaskStore) async throws {
        guard let originalTask else { return }
        var fields: [String: JSONValue] = [:]
        if trimmedTitle != originalTask.title { fields["title"] = .string(trimmedTitle) }
        let desc = taskDescription.isEmpty ? nil : taskDescription
        if desc != originalTask.description { fields["description"] = desc.map { JSONValue.string($0) } ?? .null }
        let dueStr = dueDate.map(DateFormats.calendarDateString)
        if dueStr != originalTask.dueDate { fields["due_date"] = dueStr.map { JSONValue.string($0) } ?? .null }
        let startStr = startMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        if startStr != originalTask.startTime { fields["start_time"] = startStr.map { JSONValue.string($0) } ?? .null }
        if durationMin != originalTask.durationMin { fields["duration_min"] = durationMin.map { JSONValue.number(Double($0)) } ?? .null }
        if projectId != originalTask.projectId { fields["project_id"] = projectId.map { JSONValue.string($0) } ?? .null }
        if priority.rawValue != originalTask.priority { fields["priority"] = .number(Double(priority.rawValue)) }
        if assigneeId != originalTask.assigneeId { fields["assignee_id"] = assigneeId.map { JSONValue.string($0) } ?? .null }
        let originalLabelIds = Set(originalTask.labels.map(\.id))
        if selectedLabelIds != originalLabelIds { fields["label_ids"] = .strings(Array(selectedLabelIds)) }

        guard !fields.isEmpty else { return }
        _ = await taskStore.patch(taskId: taskID, fields: fields) { _ in }
    }

    private func saveCreate(trimmedTitle: String, taskStore: TaskStore) async throws {
        let payload = APIClient.NewTaskRequest(
            title: trimmedTitle,
            description: taskDescription.isEmpty ? nil : taskDescription,
            dueDate: dueDate.map(DateFormats.calendarDateString),
            startTime: startMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) },
            durationMin: durationMin,
            projectId: projectId,
            assigneeId: assigneeId,
            priority: priority.rawValue,
            parentId: parentId,
            labelIds: selectedLabelIds.isEmpty ? nil : Array(selectedLabelIds),
            subtasks: subtaskDrafts.isEmpty ? nil : subtaskDrafts.map(\.title)
        )
        guard let created = await taskStore.create(payload) else {
            throw APIError.server(status: 0, message: "Не удалось сохранить задачу")
        }
        // Файлы, накопленные локально до создания задачи — заливаем теперь,
        // когда id наконец известен (см. `AttachmentsFieldView.swift`).
        await attachments.flushPending(taskId: created.id)
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
