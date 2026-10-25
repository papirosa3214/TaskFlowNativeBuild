import Foundation
import Observation

/// Стор задач — загрузка, кэш в памяти, оптимистичные изменения с откатом,
/// приём реалтайм-событий. spec/API.md §8: у веба списки инвалидируются
/// целиком при любой мутации (react-query, довольно грубо) — здесь сделано
/// ТОЧЕЧНО (заменить/добавить/убрать один элемент), это не расхождение с
/// контрактом сервера, только другая (более дешёвая) стратегия кэша на
/// стороне клиента, спека явно разрешает это решать автору клиента.
@MainActor
@Observable
public final class TaskStore {
    public private(set) var tasks: [ApiTask] = [] {
        // Ревизия списка: растёт при ЛЮБОМ изменении. Экрану «Сегодня» она
        // нужна вместо сравнения самих задач: `ApiTask` — это десятки полей,
        // и сравнение списка по значению на каждый проход `body` стоило
        // дороже, чем вся пересборка снимка.
        didSet { tasksRevision += 1 }
    }
    public private(set) var archivedTasks: [ApiTask] = []
    /// Счётчик событий «карточка ушла в архив». Экран «Состояние системы»
    /// слушает его и перечитывает сводку и ленту уведомлений: запись
    /// поломки должна исчезнуть сразу после архива, а не после ручного
    /// обновления (владелец 20.10.2026).
    public private(set) var archivedRevision = 0
    public private(set) var isLoadingArchive = false
    public var archiveErrorMessage: String?
    /// Тот же список, но С ДОЧЕРНИМИ (`include_children`). Только для плиток
    /// «Обзора» и «Работы агентов»: работу там ведут именно дочерние, а в
    /// `tasks` сервер кладёт лишь те из них, у кого есть проект — дочерняя
    /// «в работе» в плитках не считалась (владелец 22.09.2026). `tasks` не
    /// расширяем: иначе дочерние вывалились бы строками во все списки.
    public private(set) var agentWorkTasks: [ApiTask] = [] {
        didSet { tasksRevision += 1 }
    }

    /// Ревизия списка задач. Меняется при любой правке `tasks` или
    /// `agentWorkTasks` — по ней экраны понимают, что список изменился, не
    /// сравнивая сами задачи.
    public private(set) var tasksRevision = 0
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let apiClient: APIClient
    /// Курсор синхронизации: с какого момента клиент догоняет дельту
    /// (вариант B трафика). Живёт в памяти сессии: после перезапуска
    /// приложения список всё равно перечитывается целиком.
    @ObservationIgnored private var syncCursor: String?
    /// ETag последней выдачи списка: по нему сервер отвечает 304, если
    /// список не менялся (тело не качаем).
    @ObservationIgnored private var listETag: String?
    @ObservationIgnored private var realtimeLoads: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var realtimeVersions: [String: Int] = [:]
    @ObservationIgnored private var realtimeLoadIDs: [String: UUID] = [:]

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// `silent` — обновление в фоне, без спиннера. Нужно для рефетча после
    /// переподключения: спиннер вставлялся блоком в начало ленты, список
    /// прыгал, и владелец видел это как «экран моргает сам по себе».
    public func load(silent: Bool = false) async {
        if !silent { isLoading = true }
        errorMessage = nil
        defer { if !silent { isLoading = false } }
        // ОДИН запрос вместо двух. Сервер отдаёт список вместе с дочерними
        // (`include_children=true`), а корневые выделяются локально по тому же
        // правилу, что и на сервере (`server/src/routes/tasks.ts`:
        // `parent_id IS NULL OR project_id IS NOT NULL`) — сверено на живых
        // данных: 126 корневых совпадают с серверным списком до id. Раньше
        // телефон скачивал весь список дважды (1,83 МБ каждый) ради единиц
        // дочерних карточек — половина трафика уходила в дубль.
        do {
            let page = try await apiClient.taskList(includeChildren: true, etag: listETag)
            if page.notModified {
                // Список не менялся — сервер ответил 304 без тела. Качать
                // 402 КБ gzip впустую не нужно, состояние уже актуально.
                if let cursor = page.cursor { syncCursor = cursor }
                return
            }
            let all = page.tasks
            agentWorkTasks = all.filter { !$0.isArchived }
            tasks = all.filter { !$0.isArchived && Self.isRootTask($0) }
            listETag = page.etag
            if let cursor = page.cursor { syncCursor = cursor }
        } catch is CancellationError {
            // Экран перезапросил список раньше, чем доехал предыдущий заход
            // (смена формата «Список»/«Один день», быстрый повторный вход) —
            // отмена штатная, банер «Сеть недоступна» тут ни при чём.
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Корневая карточка — по правилу сервера (`server/src/routes/tasks.ts`):
    /// `parent_id IS NULL OR project_id IS NOT NULL`. Сверено на живых данных:
    /// 126 корневых из 127 совпадают с серверным списком до id.
    private static func isRootTask(_ task: ApiTask) -> Bool {
        task.parentId == nil || task.projectId != nil
    }

    /// Партиальная правка с оптимистичным откликом: локальная копия меняется
    /// СРАЗУ через `apply`, запрос уходит в фоне; при ошибке — откат к
    /// снимку до правки (spec §8: у веба это точечный приём, не универсальный,
    /// используется в первую очередь для быстрых визуальных изменений вроде
    /// перетаскивания — здесь доступен любому вызывающему коду).
    @discardableResult
    public func patch(taskId: String, fields: [String: JSONValue], apply: (inout ApiTask) -> Void) async -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return false }
        let snapshot = tasks[index]
        apply(&tasks[index])
        do {
            let updated = try await apiClient.patchTask(id: taskId, fields: fields)
            if let freshIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[freshIndex] = updated
            }
            return true
        } catch {
            // Сервер не знает такой задачи — значит наш список протух: её
            // успели удалить в другом месте, а строка ещё висит на экране.
            // Пугать этим владельца незачем (15.09.2026: «пишет, что она
            // удалена, но она не удалена» — путаница шла именно отсюда):
            // просто убираем строку и подтягиваем свежий список.
            if Self.isMissingRecord(error) {
                tasks.removeAll { $0.id == taskId }
                await load(silent: true)
                return false
            }
            if let freshIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[freshIndex] = snapshot
            }
            errorMessage = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    public func create(_ payload: APIClient.NewTaskRequest) async -> ApiTask? {
        do {
            let created = try await apiClient.createTask(payload)
            tasks.append(created)
            return created
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    public func loadArchive() async {
        isLoadingArchive = true
        archiveErrorMessage = nil
        defer { isLoadingArchive = false }
        do {
            archivedTasks = try await apiClient.tasks(includeChildren: true, archived: true)
                .filter { $0.isArchived }
        } catch is CancellationError {
        } catch {
            archiveErrorMessage = Self.message(for: error)
        }
    }

    @discardableResult
    public func delete(taskId: String) async -> Bool {
        errorMessage = nil
        do {
            let archived = try await apiClient.archiveTask(id: taskId)
            guard archived.isArchived else {
                errorMessage = "Сервер не подтвердил архивирование задачи."
                return false
            }
            upsert(archived)
            await load(silent: true)
            await loadArchive()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    public func restore(taskId: String) async -> Bool {
        archiveErrorMessage = nil
        do {
            let restored = try await apiClient.restoreTask(id: taskId)
            guard !restored.isArchived else {
                archiveErrorMessage = "Сервер не подтвердил восстановление задачи."
                return false
            }
            upsert(restored)
            await load(silent: true)
            await loadArchive()
            return true
        } catch {
            archiveErrorMessage = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    public func permanentlyDelete(taskId: String) async -> Bool {
        guard archivedTasks.contains(where: { $0.id == taskId && $0.isArchived }) else {
            archiveErrorMessage = "Окончательное удаление доступно только из архива."
            return false
        }
        archiveErrorMessage = nil
        do {
            try await apiClient.permanentlyDeleteTask(id: taskId)
            archivedTasks.removeAll { $0.id == taskId }
            await loadArchive()
            return true
        } catch {
            archiveErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Приём событий `RealtimeClient.onEvent` — вызывающая сторона (обычно
    /// `TaskFlowApp`) подписывает этот метод один раз при старте.
    public func apply(_ event: RealtimeEvent) {
        switch event {
        case .taskCreated(let task), .taskUpdated(let task), .taskCompleted(let task), .taskState(let task):
            realtimeLoads.removeValue(forKey: task.id)?.cancel()
            upsert(task)
        case .taskChanged(let id):
            realtimeVersions[id, default: 0] += 1
            guard realtimeLoads[id] == nil else { return }
            let loadID = UUID()
            realtimeLoadIDs[id] = loadID
            realtimeLoads[id] = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.realtimeLoadIDs[id] == loadID {
                        self.realtimeLoads[id] = nil
                        self.realtimeLoadIDs[id] = nil
                    }
                }
                repeat {
                    let version = self.realtimeVersions[id]
                    guard let task = try? await self.apiClient.task(id: id), !Task.isCancelled else { return }
                    self.upsert(task)
                    if self.realtimeVersions[id] == version { return }
                } while !Task.isCancelled
            }
        case .taskDeleted(let id):
            realtimeLoads.removeValue(forKey: id)?.cancel()
            tasks.removeAll { $0.id == id }
            agentWorkTasks.removeAll { $0.id == id }
            archivedTasks.removeAll { $0.id == id }
        default:
            break
        }
    }

    /// После восстановления связи (`RealtimeClient.onReconnected`) — сервер
    /// не хранит очередь пропущенного за время разрыва (spec §4.2), поэтому
    /// рефетч списка задач, а не точечная синхронизация.
    ///
    /// Архив сюда НЕ входит: он весит ~547 КБ (95 КБ в gzip) и нужен
    /// только на экране «Архив», который грузит его сам. Раньше каждый
    /// разрыв связи тянул весь архив вместе со списком задач.
    public func refreshAfterReconnect() async {
        guard let cursor = syncCursor else {
            // Курсора нет (первый запуск сессии) — догонять нечего, читаем
            // список целиком.
            await load(silent: true)
            return
        }
        do {
            let delta = try await apiClient.taskChanges(since: cursor)
            if delta.full {
                // Журнал изменений не покрывает нужный момент — дешевле
                // один полный список, чем догонять по одной.
                await load(silent: true)
                return
            }
            await apply(delta)
            syncCursor = delta.serverTime
        } catch {
            // Дельта не вышла — список оставлять старым нельзя, читаем
            // целиком (старая цена, но правильные данные).
            await load(silent: true)
        }
    }

    /// Наложить дельту на локальный список: изменившиеся карточки — точечно
    /// (тем же путём, что и по событию сокета), исчезнувшие — убрать.
    private func apply(_ delta: APIClient.TaskChanges) async {
        var byId = Dictionary(uniqueKeysWithValues: agentWorkTasks.map { ($0.id, $0) })
        for id in delta.removedIds {
            byId.removeValue(forKey: id)
        }
        for id in delta.changedIds {
            if let task = try? await apiClient.task(id: id) {
                byId[task.id] = task
            }
        }
        // Порядок — как у полной выдачи (сервер сортирует по created_at DESC).
        let all = byId.values.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        agentWorkTasks = all.filter { !$0.isArchived }
        tasks = all.filter { !$0.isArchived && Self.isRootTask($0) }
    }

    private func upsert(_ task: ApiTask) {
        if task.isArchived {
            archivedRevision += 1
            tasks.removeAll { $0.id == task.id }
            agentWorkTasks.removeAll { $0.id == task.id }
            if let index = archivedTasks.firstIndex(where: { $0.id == task.id }) {
                archivedTasks[index] = task
            } else {
                archivedTasks.append(task)
            }
            return
        }
        archivedTasks.removeAll { $0.id == task.id }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        if let index = agentWorkTasks.firstIndex(where: { $0.id == task.id }) {
            agentWorkTasks[index] = task
        } else {
            agentWorkTasks.append(task)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// Сервер сказал именно «такой записи нет». Отсутствующий МАРШРУТ сюда
    /// не относится: по нему выводы о судьбе задачи делать нельзя — запись
    /// жива, это у сервера нет нужной ручки.
    private static func isMissingRecord(_ error: Error) -> Bool {
        if case .notFound = (error as? APIError) { return true }
        return false
    }
}
