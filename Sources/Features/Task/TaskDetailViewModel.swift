import Foundation
import Observation
import UniformTypeIdentifiers

// Вью-модель карточки задачи — spec/SCREENS-1.md §5.4. Один точечный GET
// (`useTask(id)` в спеке) отдаёт задачу СРАЗУ с `comments`/`events`/
// `attachments`/`children` (spec/API.md §5.1) — после любой мутации проще и
// надёжнее перезапросить его целиком, чем вести россыпь точечных патчей
// локального состояния (комментарии/события/подзадачи тесно связаны).
@MainActor
@Observable
final class TaskDetailViewModel {
    let taskID: String
    private let apiClient = APIClient()

    var task: ApiTask?
    var isLoading = false
    var notFound = false
    var loadErrorMessage: String?
    var actionErrorMessage: String?

    /// Чем агент занят прямо сейчас — пусто, когда задачу никто не держит.
    var activity: ApiTaskActivity = .idle

    private var pollTask: Task<Void, Never>?
    var commentText = ""
    var pendingCommentAttachments: [(id: String, name: String)] = []

    init(taskID: String) {
        self.taskID = taskID
    }

    var journalEntries: [TaskJournalEntry] {
        TaskJournalEntry.merged(comments: task?.comments ?? [], events: task?.events ?? [])
    }

    var openSubtasksCount: Int {
        (task?.subtasks ?? []).count { !$0.done }
    }

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            task = try await apiClient.task(id: taskID)
        } catch let error as APIError {
            if case .notFound = error { notFound = true } else { loadErrorMessage = Self.message(error) }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    /// Тихий перезапрос — для опроса и для «потянуть вниз»: без спиннера на
    /// весь экран и без сброса уже показанной задачи, иначе карточка мигала бы
    /// каждые полминуты.
    func reload() async {
        do {
            task = try await apiClient.task(id: taskID)
            loadErrorMessage = nil
        } catch let error as APIError {
            if case .notFound = error { notFound = true }
        } catch {}
    }

    /// Тянут вниз — обновляем и задачу, и строку активности разом.
    func refresh() async {
        await reload()
        await loadActivity()
    }

    // MARK: - Живое обновление, пока карточка открыта

    /// Открытая карточка сама себя обновляет: экран задачи не подписан на
    /// сокет (`TaskStore` держит список, но не карточку целиком с шагами,
    /// комментариями и лентой), поэтому иначе состояние шага замирало бы в том
    /// виде, в каком было при открытии. Ровно так же сделано в вебе
    /// (`src/screens/TaskDetailScreen.tsx`), и владелец 09.09.2026 заметил
    /// расхождение: «в вебе крутилка есть, в приложении нет».
    ///
    /// Каденс: активность — 15 с (сервер этим же запросом узнаёт, что на
    /// карточку смотрят, и только тогда зовёт локальную модель за пересказом),
    /// задача — 30 с, как в вебе, чтобы поймать смену состояния шага и
    /// переход «работает → пропал».
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                await self.loadActivity()
                tick += 1
                // Задачу — каждый второй проход, то есть раз в 30 секунд.
                if tick % 2 == 0 { await self.reload() }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Строка активности. Молча гасим при любой ошибке: это украшение поверх
    /// карточки, ронять из-за него экран нельзя.
    func loadActivity() async {
        guard let state = task?.agentState else {
            activity = .idle
            return
        }
        // Агент не держит задачу или пропал — сервер всё равно ответит
        // пустым, но лишний запрос каждые 15 секунд не нужен.
        guard state == .inProgress, task?.agentStale != true else {
            activity = .idle
            return
        }
        activity = (try? await apiClient.taskActivity(taskId: taskID)) ?? .idle
    }

    // MARK: - Задача целиком

    func delete(taskStore: TaskStore) async {
        await taskStore.delete(taskId: taskID)
    }

    func complete() async {
        do {
            _ = try await apiClient.patchTask(id: taskID, fields: ["status": .string("completed")])
            await load()
        } catch {
            actionErrorMessage = Self.message(error)
        }
    }

    func reopen() async {
        do {
            _ = try await apiClient.patchTask(id: taskID, fields: ["status": .string("active")])
            await load()
        } catch {
            actionErrorMessage = Self.message(error)
        }
    }

    // MARK: - Подзадачи

    func toggleSubtaskDone(_ subtask: ApiSubtask) async {
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["done": .bool(!subtask.done)])
            await load()
        } catch {
            actionErrorMessage = Self.message(error)
        }
    }

    /// «Принять» шаг на проверке — как и владельческое «Принять» задачи,
    /// закрывает шаг (сервер сам снимает `agent_state`, когда `done=true`,
    /// см. `withSubtaskState()`). Отдельного эндпоинта под конкретно
    /// «принять шаг на проверке» спека не называет.
    func acceptSubtask(_ subtask: ApiSubtask) async {
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["done": .bool(true)])
            await load()
        } catch {
            actionErrorMessage = Self.message(error)
        }
    }

    /// Ответ владельца на заблокированный/сданный на проверку шаг —
    /// ⚠️ допущение: контракт `/subtasks/:id/work` спекой не раскрыт до
    /// точной формы тела, поэтому текст владельца пишется в `result` через
    /// обычный `PATCH /subtasks/:id` (поле для отчёта уже есть в модели) —
    /// сказано в отчёте как место, требующее сверки с живым сервером.
    func replyToSubtask(_ subtask: ApiSubtask, text: String) async {
        do {
            _ = try await apiClient.patchSubtask(id: subtask.id, fields: ["result": .string(text)])
            await load()
        } catch {
            actionErrorMessage = Self.message(error)
        }
    }

    // MARK: - Лента: комментарии

    func sendComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingCommentAttachments.isEmpty else { return }
        do {
            _ = try await apiClient.createComment(taskId: taskID, text: text, attachmentIds: pendingCommentAttachments.map(\.id))
            commentText = ""
            pendingCommentAttachments = []
            await load()
        } catch {
            // Формулировка дословно из спеки §19.2.
            actionErrorMessage = "Не удалось отправить — попробуйте ещё раз"
        }
    }

    func attachCommentFile(url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let fileName = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        if let reason = TaskAttachmentDisplay.rejectionReason(fileName: fileName, mime: mime, size: data.count) {
            actionErrorMessage = reason
            return
        }
        guard let attachment = try? await apiClient.uploadTaskAttachment(taskId: taskID, kind: "comment", fileName: fileName, data: data, mime: mime) else {
            actionErrorMessage = "Не удалось приложить файл"
            return
        }
        pendingCommentAttachments.append((id: attachment.id, name: fileName))
    }

    func removePendingCommentAttachment(at index: Int) {
        guard pendingCommentAttachments.indices.contains(index) else { return }
        pendingCommentAttachments.remove(at: index)
    }

    // MARK: - Действия владельца над агентской работой (§19.2 AgentOwnerActions)

    func performOwnerAction(_ kind: AgentOwnerActionKind, comment: String?) async {
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
            await load()
        } catch {
            // Формулировка дословно из спеки §19.2.
            actionErrorMessage = "Не удалось изменить состояние задачи"
        }
    }

    // MARK: - Вложения задачи (не в ленте — kind="task")

    func attachTaskFile(url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let fileName = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        if let reason = TaskAttachmentDisplay.rejectionReason(fileName: fileName, mime: mime, size: data.count) {
            actionErrorMessage = reason
            return
        }
        do {
            _ = try await apiClient.uploadTaskAttachment(taskId: taskID, kind: "task", fileName: fileName, data: data, mime: mime)
            await load()
        } catch {
            actionErrorMessage = "Не удалось приложить файл"
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
