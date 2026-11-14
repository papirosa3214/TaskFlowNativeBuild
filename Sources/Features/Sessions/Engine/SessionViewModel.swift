import Foundation
import NewChatCore
import Observation

struct SessionTimelineItem: Identifiable, Equatable {
    enum Kind: Equatable { case message, tool, result }

    let id: String
    let entryID: String?
    let kind: Kind
    let role: String
    let title: String
    let text: String
    let isError: Bool
    /// Разметка ответа от сервера (text_blocks), как у сообщений чата.
    var blocks: [ChatServerBlock]? = nil
}

struct SessionLiveActivity: Identifiable, Equatable {
    enum Kind: Equatable { case tool, queue, retry, compaction, unknown }
    enum Status: Equatable { case running, completed, failed }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let status: Status
}

enum SessionSheet: String, Identifiable {
    case tree
    var id: String { rawValue }
}

@MainActor
@Observable
final class SessionViewModel {
    private(set) var state = SessionState(snapshot: nil)
    private(set) var sessions: [SessionSummary] = []
    private(set) var liveActivities: [SessionLiveActivity] = []
    /// Идущий ход в модели хода роли — для живой ленты как в старой комнате.
    private(set) var liveTurn = SessionLiveTurn()
    private(set) var isLoading = false
    private(set) var isLiveTurnStopped = false
    private(set) var models: [RuntimeModel] = []
    private(set) var isLoadingModels = false
    /// Ошибка каталога моделей не всплывает баннером: она нужна только в шторке
    /// выбора, а подпись модели в поле ввода живёт и без каталога.
    private(set) var modelsError: String?
    var isModelPickerPresented = false
    var composerText = ""
    var promptMode: SessionPromptMode = .prompt
    var presentedSheet: SessionSheet?
    var errorMessage: String?
    /// Отправленное, но ещё не вернувшееся с сервера сообщение владельца.
    /// Поле ввода очищается сразу, а своё сообщение раньше появлялось только
    /// эхом сервера — до него оно «пропадало» (владелец 13.11.2026:
    /// «сообщения вообще не доходят»).
    var pendingOutgoing: String?
    /// В живом ходе могла остаться дыра: после долгого обрыва сервер прислал
    /// снимок целиком вместо пропущенных кусков. Тогда по концу хода текст
    /// берём из снимка, а не оставляем ход с дырой.
    private var liveTurnHasGaps = false
    /// Курсор, до которого живой ход уже показал ленту. Ход наполняется не
    /// только ответом на сброс: часть его окна могла быть применена к нему по
    /// сокету ещё до запроса. Поэтому повтор в сохранённый ход отсекается по
    /// этому курсору, а не по источнику события (ревью владельца 14.11.2026).
    private var liveTurnPoint: SessionEventPoint?

    private var sessionGeneration: UInt64 = 0
    /// Очередь установки снимка: ответы не по порядку и события, пришедшие
    /// за время запроса, не должны ни затирать новый снимок, ни пропадать
    /// (`SessionSnapshotGate`).
    @ObservationIgnored private var snapshotGate = SessionSnapshotGate()
    /// Окно снимка: сколько событий открытой сессии легло в состояние —
    /// снимок ставится только при пустом окне (`SessionSnapshotGate`). Метку
    /// двигают все пути, которые меняют состояние: живые события и догнанные
    /// после переподключения, включая замену по `resetRequired`
    /// (`SessionEventWindow`).
    @ObservationIgnored private var sessionWindow = SessionEventWindow()
    /// События открытой сессии, принятые по сокету, пока ответ на сброс в пути
    /// (см. `receive`). Читаются и очищаются в `recoverAfterReconnect`.
    @ObservationIgnored private var reconnectBuffer: [SessionEventEnvelope] = []
    /// Кто владеет очередью событий, принятых во время догона: сессия и
    /// уникальный номер запроса. Одного `sessionID` мало: при A→B→A поздний
    /// ответ старого запроса A считал бы очередь нового A своей, забрал бы
    /// её и снял бы его флаг, а его `catch` — тем более (ревью владельца
    /// 14.11.2026).
    private struct ReconnectFetch: Equatable {
        let sessionID: String
        let token: UInt64
    }
    @ObservationIgnored private var reconnectFetch: ReconnectFetch?
    @ObservationIgnored private var reconnectFetchSeq: UInt64 = 0
    /// Очередь упёрлась в потолок и выбросила передние события: окно уже не
    /// полное, курсор за эту дыру не двигается (см. `recoverAfterReconnect`).
    @ObservationIgnored private var reconnectBufferTruncated = false
    /// Дыра, которую закроет повтор догона (усечённая очередь). Пока она
    /// есть, догон просит от неё, хотя живые события уже увели `lastCursor`
    /// вперёд. `eventsLost` сюда не попадает: вытесненное сервером повтором
    /// не восстановить, и курсор за него не держится (ревью владельца
    /// 14.11.2026).
    @ObservationIgnored private var recoveryCursor: String?
    /// Потолок очереди — 512, как буфер ленты сервера. Упереться в него
    /// можно и на долгом запросе: тогда окно считается неполным, а не
    /// молча усечённым.
    private static let reconnectBufferLimit = 512

    /// Лента для экрана: история, живые реплики и ещё не подтверждённое
    /// сообщение владельца в конце, пока сервер не прислал его сам.
    var displayRows: [SessionFeedRow] {
        var history = feedRows
        // Пока на экране напечатанный ход, его же записи из снимка не
        // показываем: хвост после последнего сообщения владельца.
        if !liveTurn.isEmpty,
           let lastUser = history.lastIndex(where: { if case .user = $0 { return true } else { return false } }) {
            history = Array(history[...lastUser])
        }
        let rows = history + liveFeedRows
        guard let pending = pendingOutgoing else { return rows }
        let lastUser = rows.last { if case .user = $0 { return true } else { return false } }
        if case .user(_, let text)? = lastUser,
           text.trimmingCharacters(in: .whitespacesAndNewlines) == pending { return rows }
        return rows + [.user(id: "pending-outgoing", text: pending)]
    }

    private let apiClient: SessionAPIClient
    private let realtime: SessionRealtimeClient
    private var hasStarted = false
    private var pendingPrompt: PromptSessionRequest?

    init(apiClient: SessionAPIClient, realtime: SessionRealtimeClient) {
        self.apiClient = apiClient
        self.realtime = realtime
    }

    var activeSessionID: String? { state.snapshot?.id }
    var isStreaming: Bool { state.snapshot?.isStreaming == true }

    // MARK: - Модель сессии

    /// Модель, на которой идёт тред. Источник — сервер: Pi держит её в сессии,
    /// поэтому переживает перезапуск и видна в истории.
    var currentModel: SessionModelRef? { state.snapshot?.model }

    /// Подпись модели для поля ввода: имя из каталога, иначе id.
    var currentModelTitle: String {
        guard let currentModel else { return "Модель" }
        return modelTitle(provider: currentModel.provider, id: currentModel.id)
    }

    func modelTitle(provider: String, id: String) -> String {
        models.first { $0.provider == provider && $0.id == id }?.displayName ?? id
    }

    /// Доступные модели по провайдерам: только те, чей провайдер авторизован, —
    /// остальные всё равно не ответят.
    struct ModelGroup: Identifiable {
        let id: String
        let title: String
        let models: [RuntimeModel]
    }

    var availableModelGroups: [ModelGroup] {
        let available = models.filter(\.available)
        let grouped = Dictionary(grouping: available, by: \.provider)
        return grouped
            .map { provider, list in
                ModelGroup(
                    id: provider,
                    title: Self.providerTitle(provider),
                    models: list.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func loadModels() async {
        guard models.isEmpty else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            // Каталог моделей — общий с остальным TaskFlow.
            models = try await APIClient().runtimeModels()
            modelsError = nil
        } catch {
            modelsError = error.localizedDescription
        }
    }

    /// Смена модели идёт через сервер: он проверяет авторизацию провайдера и
    /// пишет model_change в транскрипт. Ошибку показываем в шторке выбора.
    func selectModel(provider: String, id: String) async throws {
        guard let sessionID = activeSessionID else { return }
        let response = try await apiClient.setSessionModel(
            sessionID: sessionID,
            request: SetSessionModelRequest(requestId: UUID().uuidString, provider: provider, model: id)
        )
        installSnapshot(response.session)
    }

    static func providerTitle(_ provider: String) -> String {
        providerNames[provider] ?? provider
    }

    private static let providerNames: [String: String] = [
        "anthropic": "Anthropic",
        "openai": "OpenAI",
        "openai-codex": "OpenAI Codex",
        "minimax": "MiniMax",
        "opencode-go": "OpenCode Go",
        "opencode": "OpenCode",
        "google": "Google",
        "deepseek": "DeepSeek",
        "openrouter": "OpenRouter",
        "ollama": "Ollama",
        "xai": "xAI",
        "moonshot": "Moonshot",
        "mistral": "Mistral",
        "groq": "Groq",
        "cerebras": "Cerebras",
        "amazon-bedrock": "Amazon Bedrock",
        "azure": "Azure",
        "zai": "Z.ai",
    ]

    var title: String {
        if let name = state.snapshot?.name, !name.isEmpty { return name }
        if let name = activeSummary?.name, !name.isEmpty { return name }
        switch activeSummary?.relation {
        case .fork: return "Ответвлённая сессия"
        case .subagent: return "Дочерняя сессия"
        default: return "Помощник владельца"
        }
    }

    /// Подзаголовок нативной шапки: рабочий каталог и модель, без своих строк состояния.
    var subtitle: String {
        guard let snapshot = state.snapshot else { return "" }
        return [snapshot.cwd, modelName].compactMap { $0 }.joined(separator: " · ")
    }

    var modelName: String? {
        if let currentModel { return currentModelTitle }
        guard let snapshot = state.snapshot else { return nil }
        for entry in snapshot.entries.reversed() {
            guard case let .object(object) = entry else { continue }
            if object.string("type") == "model_change", let model = object.string("modelId") {
                return model
            }
            if let message = object.object("message"),
               message.string("role") == "assistant",
               let model = message.string("model") {
                return model
            }
        }
        return nil
    }

    var activeSummary: SessionSummary? {
        sessions.first { $0.id == activeSessionID }
    }
    var contextDetails: String {
        guard let snapshot = state.snapshot else { return "" }
        var model: String?
        var thinking: String?
        for entry in snapshot.entries.reversed() {
            guard case let .object(object) = entry else { continue }
            if thinking == nil {
                thinking = object.string("thinkingLevel")
                    ?? object.object("message")?.string("thinkingLevel")
            }
            if model == nil {
                if object.string("type") == "model_change" {
                    model = object.string("modelId")
                } else if let message = object.object("message"), message.string("role") == "assistant" {
                    model = message.string("model")
                }
            }
            if model != nil, thinking != nil { break }
        }
        return [snapshot.cwd, model, thinking.map { "thinking: \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
    var isSendingCommand: Bool {
        if case .sending = state.commandDelivery { return true }
        return false
    }
    var childSessions: [SessionSummary] {
        guard let sessionFile = state.snapshot?.sessionFile else { return [] }
        return sessions.filter { $0.parentSession == sessionFile }
    }

    /// Записи снимка разбираются один раз на снимок, а не на каждую
    /// перерисовку: клиент тонкий, разметку готовит сервер (владелец 12.11.2026).
    @ObservationIgnored private var persistedCache: (key: String, items: [SessionTimelineItem]) = ("", [])

    @ObservationIgnored private var feedCache: (key: String, rows: [SessionFeedRow]) = ("", [])

    /// История сессии ходами: реплики, размышления и шаги, ответы.
    var feedRows: [SessionFeedRow] {
        let entries = state.snapshot?.entries ?? []
        let key = "\(state.snapshot?.id ?? "")#\(entries.count)#\(state.snapshot?.leafId ?? "")"
        if feedCache.key == key { return feedCache.rows }
        let rows = SessionFeed.rows(entries: entries)
        feedCache = (key, rows)
        return rows
    }

    /// Сообщения после снимка, пришедшие событиями: реплики владельца и —
    /// пока живого хода нет — готовые ответы.
    var liveFeedRows: [SessionFeedRow] {
        state.messages.enumerated().compactMap { index, message in
            let id = message.id ?? "live-\(index)-\(message.role)"
            if message.role == "user" { return .user(id: id, text: message.text) }
            if message.role == "assistant", liveTurn.isEmpty, !message.text.isEmpty {
                // Разметка — та же, что в истории: текст и блоки из события
                // сервера (`message_end`). Без неё экран показал бы «Не удалось
                // получить подготовленное содержимое» вместо самого ответа.
                return .reply(id: id, reply: SessionReply(
                    text: message.text, blocks: SessionLiveTurn.blocks(message.blocks)
                ))
            }
            return nil
        }
    }

    private var persistedItems: [SessionTimelineItem] {
        let entries = state.snapshot?.entries ?? []
        let key = "\(state.snapshot?.id ?? "")#\(entries.count)#\(state.snapshot?.leafId ?? "")"
        if persistedCache.key == key { return persistedCache.items }
        let items = entries.flatMap(Self.items(from:))
        persistedCache = (key, items)
        return items
    }

    var timeline: [SessionTimelineItem] {
        let persisted = persistedItems
        let live = state.messages.enumerated().map { index, message in
            SessionTimelineItem(
                id: "live-\(index)-\(message.role)-\(message.text.hashValue)",
                entryID: nil,
                kind: .message,
                role: message.role,
                title: Self.roleTitle(message.role),
                text: message.text,
                isError: false
            )
        }
        return persisted + live
    }

    /// Точка входа — список сессий. Корневая сессия открывается только если списка нет.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await apiClient.listSessions().sessions
            if sessions.isEmpty {
                let response = try await apiClient.openRoot()
                installSnapshot(response.session)
                sessions = try await apiClient.listSessions().sessions
            }
            realtime.connect(
                onEvent: { [weak self] event in self?.receive(event) },
                onReconnect: { [weak self] in await self?.recoverAfterReconnect() }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Перечитать снимок сессии (после голосового разговора реплики голоса
    /// пишет сервер мимо потока событий).
    func refresh() async {
        await refreshSnapshot()
    }

    func reload() async {
        await refreshSessions()
    }

    func openRoot() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await apiClient.openRoot()
            installSnapshot(response.session)
            await refreshSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ sessionID: String) async {
        guard sessionID != activeSessionID else {
            presentedSheet = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await apiClient.snapshot(sessionID: sessionID)
            installSnapshot(response.session)
            presentedSheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Открыть сессию для экрана: существующую по id или новую.
    func open(sessionID: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = if let sessionID {
                try await apiClient.snapshot(sessionID: sessionID)
            } else {
                try await apiClient.createSession()
            }
            installSnapshot(response.session)
            if !hasStarted {
                hasStarted = true
                realtime.connect(
                    onEvent: { [weak self] event in self?.receive(event) },
                    onReconnect: { [weak self] in await self?.recoverAfterReconnect() }
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        realtime.disconnect()
    }

    func send() async {
        guard let sessionID = activeSessionID else { return }
        // Как у Claude Code: пока сессия отвечает, сообщение подмешивается в
        // идущий ответ, а не ждёт в очереди (владелец 12.11.2026).
        promptMode = isStreaming ? .steer : .prompt
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request: PromptSessionRequest
        if let pendingPrompt, pendingPrompt.text == text, pendingPrompt.mode == promptMode {
            request = pendingPrompt
        } else {
            request = PromptSessionRequest(requestId: UUID().uuidString, text: text, mode: promptMode)
            pendingPrompt = request
        }
        let requestID = request.requestId
        state.markCommandStarted(requestId: requestID)
        // Поле очищается сразу: сервер подтверждает команду только после
        // ответа, а держать текст в поле весь ответ — путаница. Ошибка вернёт его.
        composerText = ""
        // Прошлый напечатанный ход — в историю ДО нового сообщения: иначе он
        // оставался живым ходом под новым сообщением и пропадал, когда
        // начинался новый ответ (владелец 13.11.2026: «ответ исчез»). Сбрасываем
        // живой ход, только если в снимке уже есть его ответ — ничего не теряем.
        if !isStreaming, !liveTurn.isEmpty {
            await refresh()
            let tail = feedRows.reversed().prefix { if case .user = $0 { return false } else { return true } }
            if tail.contains(where: { if case .reply = $0 { return true } else { return false } }) {
                liveTurn.reset()
            }
        }
        pendingOutgoing = text
        do {
            let response = try await apiClient.prompt(
                sessionID: sessionID,
                request: request
            )
            state.markCommandAcknowledged(requestId: response.requestId)
            pendingPrompt = nil
            composerText = ""
        } catch let error as URLError where error.code == .timedOut {
            state.markCommandTimedOut(requestId: requestID)
            errorMessage = "Сервер ещё мог принять сообщение. Состояние будет уточнено после переподключения."
        } catch {
            state.markCommandFailed(requestId: requestID, message: error.localizedDescription)
            pendingPrompt = nil
            pendingOutgoing = nil
            if composerText.isEmpty { composerText = text }
            errorMessage = error.localizedDescription
        }
    }

    func abort() async {
        guard let sessionID = activeSessionID else { return }
        let generation = sessionGeneration
        let turnScope = liveTurn.scope
        let wasStreaming = isStreaming
        let requestID = UUID().uuidString
        do {
            let response = try await apiClient.abort(
                sessionID: sessionID,
                request: AbortSessionRequest(requestId: requestID)
            )
            guard activeSessionID == sessionID, sessionGeneration == generation else { return }
            // Ответ приходит после остановки сервера. Не закрываем новый ход,
            // если он успел начаться, пока запрос был в пути.
            if response.aborted == true, wasStreaming,
               let turnScope, liveTurn.scope == turnScope {
                state.snapshot?.isStreaming = false
                state.snapshot?.isIdle = true
                isLiveTurnStopped = true
            }
            await refreshSnapshot()
        } catch {
            guard activeSessionID == sessionID, sessionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func branch(from entryID: String) async {
        guard let sessionID = activeSessionID else { return }
        do {
            let response = try await apiClient.branch(
                sessionID: sessionID,
                request: SessionEntryCommandRequest(requestId: UUID().uuidString, entryId: entryID)
            )
            installSnapshot(response.session)
            presentedSheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fork(from entryID: String) async {
        guard let sessionID = activeSessionID else { return }
        do {
            let response = try await apiClient.fork(
                sessionID: sessionID,
                request: SessionEntryCommandRequest(requestId: UUID().uuidString, entryId: entryID)
            )
            sessions = try await apiClient.listSessions().sessions
            installSnapshot(response.session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func receive(_ event: SessionEventEnvelope) {
        // Ответ на сброс собирается на сервере раньше, чем доходит до клиента:
        // событие, пришедшее в это время по сокету, в него не входит. Помним
        // такие события — иначе замена состояния снимком их теряет (ревью
        // `7c7b5da0`, владелец 14.11.2026).
        if event.sessionId == reconnectFetch?.sessionID {
            if reconnectBuffer.count >= Self.reconnectBufferLimit {
                reconnectBuffer.removeFirst()
                reconnectBufferTruncated = true
            }
            reconnectBuffer.append(event)
        }
        // Окно снимка двигает только реально новое событие открытой сессии:
        // повтор уже принятого куска состояние не меняет, а сервер после
        // переподключения пересылает хвост заново — на повторах сгорали бы
        // обе попытки установки снимка.
        sessionWindow.noteLive(event, activeSessionID: activeSessionID, seenCursors: state.seenCursors)
        recordActivity(event)
        // Повтор уже принятого куска (после переподключения сервер может
        // прислать его снова) в живой ход не пишем — иначе слова двоятся.
        let isNew = !state.seenCursors.contains(event.cursor)
        if isNew, event.sessionId == activeSessionID {
            if event.type == "agent_start" {
                liveTurnHasGaps = false
            }
            updateLiveTurnStopState(event)
            liveTurn.apply(type: event.type, payload: event.payload, sessionID: event.sessionId)
            noteLiveTurnApplied(event)
        }
        SessionReducer.apply(event, to: &state)
        if event.sessionId == activeSessionID, event.type == "agent_settled" {
            Task { await refreshSnapshot() }
        } else if event.sessionId != activeSessionID, event.type == "agent_settled" {
            Task { await refreshSessions() }
        }
    }

    /// Запомнить, до какого курсора живой ход уже показал ленту. Курсор другой
    /// эпохи — другая лента: он заменяет прежний, а не сравнивается с ним.
    private func noteLiveTurnApplied(_ event: SessionEventEnvelope) {
        guard let point = event.eventPoint else { return }
        if let current = liveTurnPoint, current.epoch == point.epoch, current.seq >= point.seq {
            return
        }
        liveTurnPoint = point
    }

    private func updateLiveTurnStopState(_ event: SessionEventEnvelope) {
        if event.type == "agent_start" {
            isLiveTurnStopped = false
        } else if event.type == "agent_settled" {
            if case .bool(true)? = event.payload["aborted"] { isLiveTurnStopped = true }
            else { isLiveTurnStopped = false }
        }
    }

    private func recoverAfterReconnect() async {
        guard let sessionID = activeSessionID else { return }
        // Второй догон той же сессии не начинаем, пока идёт первый: очередь
        // событий у них общая, и второй забрал бы куски у первого.
        guard reconnectFetch?.sessionID != sessionID else {
            ClientLog.shared.add("session=\(sessionID) recover skipped in-flight")
            return
        }
        let generation = sessionGeneration
        do {
            let cursor = SessionReconnectReplay.resumeCursor(
                lastCursor: state.lastCursor, recovering: recoveryCursor
            )
            if let cursor {
                // Пока ответ в пути, сокет может принести события новее его
                // снимка: сервер собрал ответ раньше. Собираем их и проигрываем
                // после снимка — иначе они пропадают (ревью `7c7b5da0`).
                reconnectBuffer.removeAll()
                reconnectBufferTruncated = false
                // Уникальный номер запроса: им же проверяется владение
                // очередью после ответа — одного `sessionID` мало (A→B→A).
                reconnectFetchSeq &+= 1
                let fetch = ReconnectFetch(sessionID: sessionID, token: reconnectFetchSeq)
                reconnectFetch = fetch
                let payload: SessionReconnectPayload
                do {
                    payload = try await apiClient.events(sessionID: sessionID, after: cursor)
                } catch {
                    if reconnectFetch == fetch { reconnectFetch = nil }
                    throw error
                }
                // Очередь отдаётся только своему запросу: за время ответа
                // сессия могла смениться и начаться другой догон.
                let ownsBuffer = reconnectFetch == fetch
                let carried = ownsBuffer ? reconnectBuffer : []
                let carriedComplete = ownsBuffer && !reconnectBufferTruncated
                if ownsBuffer {
                    reconnectBuffer.removeAll()
                    reconnectBufferTruncated = false
                    reconnectFetch = nil
                }
                guard activeSessionID == sessionID, sessionGeneration == generation else { return }
                // Догнанные куски — и в живой ход: раньше они шли только в
                // состояние, и на экране в ответе пропадали слова (владелец
                // 13.11.2026: «какие-то слова не допечатываются»).
                ClientLog.shared.add("session=\(sessionID) recover events=\(payload.events.count) reset=\(payload.resetRequired) lost=\(payload.eventsLost) carried=\(carried.count) truncated=\(!carriedComplete)")
                if payload.resetRequired {
                    // Состояние заменяется целиком: снимок, запрос которого
                    // начат раньше восстановления, старше его даже без новых
                    // событий — иначе он ложится поверх с сохранёнными
                    // `seenCursors`, и догнанное событие пропадает навсегда.
                    sessionWindow.noteReset()
                    // Сервер `c90c2c18` отдаёт снимок и **только** окно событий
                    // после его точки. Снимок — основа; окно проигрывается в
                    // том же порядке и в состояние (там же), и в живой ход,
                    // иначе незавершённый ответ после обрыва не показывается
                    // (владелец 14.11.2026). События не новее точки и повторы
                    // отсекает `SessionReconnectReplay`: в снимке они уже есть.
                    let replay = SessionReconnectReplay.events(
                        payload, sessionID: sessionID, carried: carried
                    )
                    // Лента та же, а голову окна из неё вытеснило
                    // (`eventsLost` или потолок очереди): показанный текст
                    // сервер прислал сам, стирать его на каждом переподключении
                    // нельзя — полный текст доедет на `message_end`.
                    let point = payload.snapshot?.eventPoint
                    let previousPoint = state.lastCursor.flatMap { SessionEventPoint(cursor: $0) }
                    // Пересоздать живой ход можно только из снимка. Сброс без
                    // снимка (или без его точки) — не повод стирать на экране
                    // уже напечатанный ответ: сначала снимок, потом решение
                    // (ревью владельца 14.11.2026).
                    let canRebuildTurn = point != nil
                    let keepsLiveTurn = !canRebuildTurn
                        || ((payload.eventsLost || !carriedComplete)
                            && previousPoint?.epoch == point?.epoch)
                    // Окно для состояния — всегда целиком: его основа снимок,
                    // повтор курсором отсекает редьюсер. Живому ходу — только
                    // то, что он ещё не показал: часть окна HTTP могла быть
                    // применена к нему по сокету раньше запроса, а от
                    // известной дыры окно начинается перед концом показанного.
                    let liveReplay = SessionReconnectReplay.liveEvents(
                        payload, sessionID: sessionID, carried: carried,
                        keepingCurrent: keepsLiveTurn, appliedUpTo: liveTurnPoint
                    )
                    // Дыра, которую закроет повтор: только усечённая очередь.
                    // `eventsLost` — данные вытеснены на сервере, курсор за них
                    // не держим: иначе каждый обрыв просит вытесненную точку и
                    // снова получает сброс (ревью владельца 14.11.2026).
                    let recoverableGap = !carriedComplete && !payload.eventsLost
                    SessionReducer.apply(
                        payload, replay: replay, replayComplete: !recoverableGap, to: &state
                    )
                    recoveryCursor = recoverableGap ? point?.cursor : nil
                    if keepsLiveTurn {
                        liveTurnHasGaps = true
                    } else {
                        liveTurn.reset()
                        liveTurn.bind(sessionID: sessionID)
                        liveTurnHasGaps = false
                        liveTurnPoint = nil
                    }
                    for event in liveReplay {
                        updateLiveTurnStopState(event)
                        liveTurn.apply(type: event.type, payload: event.payload, sessionID: sessionID)
                        noteLiveTurnApplied(event)
                    }
                    // live не имеет своей точки. Используем только при отсутствии
                    // событий смены сообщения и более свежего текста; очередь
                    // сокета, пришедшая в полёте, всегда имеет приоритет.
                    if carried.isEmpty, let snapshot = payload.snapshot, snapshot.isStreaming,
                       !replay.contains(where: {
                           ["agent_start", "agent_settled", "message_start", "message_end"].contains($0.type)
                       }) {
                        liveTurn.installBridge(snapshot.live, sessionID: sessionID)
                    }
                    if keepsLiveTurn, liveReplay.count < replay.count {
                        // Честно: часть окна новее точки снимка в ход не пошла —
                        // она не новее уже показанного, и вставка её событий
                        // после более поздних откатила бы текст назад.
                        // Пропущенная середина доедет полным текстом в
                        // `message_end`, а не выдумывается здесь.
                        ClientLog.shared.add(
                            "session=\(sessionID) recover kept-turn window=\(replay.count) live=\(liveReplay.count) upTo=\(liveTurnPoint?.cursor ?? "-") skipped=\(replay.count - liveReplay.count) not-reordered"
                        )
                    }
                    if payload.eventsLost {
                        // Честно: голову части хода сервер вытеснил, повтором
                        // её не вернуть. Остаётся снимок, незавершённый ответ
                        // доедет целиком на `message_end` (контракт сервера).
                        ClientLog.shared.add(
                            "session=\(sessionID) recover gap-evicted not-recovered live=\(liveReplay.count)"
                        )
                    }
                } else {
                    // Только реально новые куски открытой сессии: их же кладём
                    // в живой ход и ими же закрываем окно снимка.
                    let fresh = SessionEventWindow.freshEvents(
                        payload.events, sessionID: sessionID, seenCursors: state.seenCursors
                    )
                    sessionWindow.noteFresh(fresh.count)
                    // Живому ходу — только не показанное им: запрос мог идти от
                    // известной дыры, и окно тогда начинается перед концом
                    // показанного (ревью владельца 14.11.2026). Состояние при
                    // этом получает всё окно: его отсекает `seenCursors`.
                    let liveFresh = SessionReconnectReplay.notShownYet(
                        fresh, appliedUpTo: liveTurnPoint
                    )
                    for event in liveFresh {
                        updateLiveTurnStopState(event)
                        liveTurn.apply(type: event.type, payload: event.payload, sessionID: sessionID)
                        noteLiveTurnApplied(event)
                    }
                    SessionReducer.apply(payload, to: &state)
                    // Запрос шёл от известной дыры (`resumeCursor`): сервер
                    // отдал всё после неё, значит, дыра закрыта.
                    recoveryCursor = nil
                }
                if state.needsSnapshotReset { await refreshSnapshot() }
            } else {
                await refreshSnapshot()
            }
            await refreshSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSnapshot() async {
        guard let sessionID = activeSessionID else { return }
        let generation = sessionGeneration
        // Две попытки: первая может попасть в окно с событиями — тогда снимок
        // отбрасывается и запрашивается заново, уже на опустевшем окне
        // (правило «пустое окно» — в `SessionSnapshotGate`).
        for attempt in 1...2 {
            let ticket = snapshotGate.begin(windowMark: sessionWindow.mark)
            do {
                let response = try await apiClient.snapshot(sessionID: sessionID)
                guard activeSessionID == sessionID, sessionGeneration == generation,
                      response.session.id == sessionID else { return }
                switch snapshotGate.verdict(ticket, windowMark: sessionWindow.mark) {
                case .install:
                    snapshotGate.markInstalled(ticket)
                    installSnapshot(response.session, preservingCursor: true)
                    return
                case .superseded:
                    ClientLog.shared.add(
                        "session=\(sessionID) snapshot=superseded serial=\(ticket.serial)"
                    )
                    return
                case .windowDirty:
                    ClientLog.shared.add(
                        "session=\(sessionID) snapshot=window-dirty serial=\(ticket.serial) attempt=\(attempt)"
                    )
                    continue
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        // Обе попытки попали в окно с событиями: снимок не ставится, но
        // состояние — живое, из самих событий (`agent_settled` в редьюсере
        // снимает `isStreaming`, так что «Стоп» не залипает). Запись в журнал:
        // без неё видно только «снимок почему-то не пришёл».
        ClientLog.shared.add("session=\(sessionID) snapshot=window-dirty-give-up")
    }

    private func refreshSessions() async {
        do {
            sessions = try await apiClient.listSessions().sessions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installSnapshot(_ snapshot: SessionSnapshot, preservingCursor: Bool = false) {
        let previousSessionID = activeSessionID
        let cursor = preservingCursor ? state.lastCursor : nil
        let seen = preservingCursor ? state.seenCursors : []
        let childActivity = state.childActivity
        let delivery = state.commandDelivery
        persistedCache = ("", [])
        state = SessionState(snapshot: snapshot)
        state.lastCursor = cursor
        state.seenCursors = seen
        state.childActivity = childActivity
        state.commandDelivery = delivery
        liveActivities = []
        // Ход принадлежит открытой сессии: живая разметка читается только
        // своим ходом, даже если два ответа совпали текстом (владелец 14.11.2026).
        // Другая сессия — другой ход: элементы и область прежнего сбрасываются.
        if previousSessionID != snapshot.id {
            sessionGeneration &+= 1
            isLiveTurnStopped = false
            // Очередь и известная дыра принадлежат прежней сессии: к новой
            // они не относятся, а чужой курсор увёл бы догон в чужую ленту.
            reconnectBuffer.removeAll()
            reconnectBufferTruncated = false
            reconnectFetch = nil
            recoveryCursor = nil
            liveTurnPoint = nil
        }
        liveTurn.bind(sessionID: snapshot.id)
        // Ход закончен — его шаги уже в записях снимка. Напечатанный ход
        // остаётся на экране как есть, без подмены записями снимка (владелец
        // 13.11.2026: «если он уже напечатался — итоговый ответ не нужен»);
        // сбрасывается на следующем `agent_start`. Если в ходе дыра — берём снимок.
        if !snapshot.isStreaming, liveTurnHasGaps {
            liveTurn.reset()
            liveTurnHasGaps = false
            liveTurnPoint = nil
        }
        if snapshot.isStreaming {
            liveTurn.installBridge(snapshot.live, sessionID: snapshot.id)
        }
        promptMode = snapshot.isStreaming ? .followUp : .prompt
    }

    private func recordActivity(_ event: SessionEventEnvelope) {
        guard event.sessionId == activeSessionID else { return }
        let activity: SessionLiveActivity?
        switch event.type {
        case "tool_start", "tool_update", "tool_end":
            let id = event.payload.string("toolCallId") ?? event.cursor
            let name = event.payload.string("toolName") ?? "Инструмент"
            let detail = event.payload["partialResult"]?.compactDescription
                ?? event.payload["result"]?.compactDescription
                ?? event.payload["args"]?.compactDescription
                ?? ""
            let isError = event.payload.bool("isError") ?? false
            let status: SessionLiveActivity.Status = event.type == "tool_end"
                ? (isError ? .failed : .completed)
                : .running
            activity = SessionLiveActivity(id: id, kind: .tool, title: name, detail: detail, status: status)
        case "queue_update":
            activity = SessionLiveActivity(
                id: event.cursor,
                kind: .queue,
                title: "Очередь сообщений",
                detail: event.payload.compactDescription,
                status: .completed
            )
        case "retry_start":
            activity = SessionLiveActivity(
                id: "retry", kind: .retry, title: "Повтор запроса",
                detail: event.payload.compactDescription, status: .running
            )
        case "retry_end":
            activity = SessionLiveActivity(
                id: "retry", kind: .retry, title: "Повтор завершён",
                detail: event.payload.compactDescription, status: .completed
            )
        case "compaction_start":
            activity = SessionLiveActivity(
                id: "compaction", kind: .compaction, title: "Сжатие контекста",
                detail: "Pi обновляет рабочий контекст сессии.", status: .running
            )
        case "compaction_end":
            activity = SessionLiveActivity(
                id: "compaction", kind: .compaction, title: "Контекст обновлён",
                detail: event.payload.compactDescription, status: .completed
            )
        case "pi_unknown":
            activity = SessionLiveActivity(
                id: event.cursor, kind: .unknown, title: "Системное событие Pi",
                detail: event.payload.string("piType") ?? "Неизвестный тип", status: .completed
            )
        default:
            activity = nil
        }
        guard let activity else { return }
        if let index = liveActivities.firstIndex(where: { $0.id == activity.id }) {
            liveActivities[index] = activity
        } else {
            liveActivities.append(activity)
        }
        if liveActivities.count > 20 { liveActivities.removeFirst(liveActivities.count - 20) }
    }

    private static func items(from entry: NewChatCore.JSONValue) -> [SessionTimelineItem] {
        guard case let .object(object) = entry else { return [] }
        let entryID = object.string("id")
        // Реплика голосового разговора в сессии (сервер, 12.11.2026).
        if object.string("type") == "custom_message", object.string("customType") == "taskflow.voice",
           let details = object.object("details"), let text = details.string("text"), !text.isEmpty {
            let role = details.string("role") == "assistant" ? "assistant" : "user"
            var item = messageItem(id: entryID ?? UUID().uuidString, entryID: entryID, role: role, text: text)
            item.blocks = serverBlocks(object["text_blocks"])
            return [item]
        }
        let messageObject = object.object("message") ?? object
        guard let role = messageObject.string("role") else { return [] }
        guard role != "system" else { return [] }
        let content = messageObject["content"]
        let baseID = entryID ?? UUID().uuidString

        switch content {
        case let .string(text):
            guard !text.isEmpty else { return [] }
            return [messageItem(id: baseID, entryID: entryID, role: role, text: text)]
        case let .array(parts):
            var items: [SessionTimelineItem] = []
            var textParts: [String] = []
            for (index, part) in parts.enumerated() {
                guard case let .object(value) = part else { continue }
                let type = value.string("type") ?? ""
                if type == "text", let text = value.string("text") {
                    textParts.append(text)
                } else if type == "toolCall" || type == "tool_use" {
                    let name = value.string("name") ?? "Инструмент"
                    items.append(SessionTimelineItem(
                        id: "\(baseID)-tool-\(index)", entryID: entryID, kind: .tool, role: role,
                        title: name,
                        text: value.object("arguments").map { NewChatCore.JSONValue.object($0).compactDescription }
                            ?? value["input"]?.compactDescription
                            ?? "",
                        isError: false
                    ))
                } else if type == "toolResult" || type == "tool_result" {
                    items.append(SessionTimelineItem(
                        id: "\(baseID)-result-\(index)", entryID: entryID, kind: .result, role: role,
                        title: "Результат", text: value["content"]?.compactDescription ?? value["result"]?.compactDescription ?? "",
                        isError: value.bool("isError") ?? false
                    ))
                }
            }
            if !textParts.isEmpty {
                let text = textParts.joined()
                if role == "toolResult" {
                    items.insert(SessionTimelineItem(
                        id: baseID,
                        entryID: entryID,
                        kind: .result,
                        role: role,
                        title: messageObject.string("toolName") ?? "Результат",
                        text: text,
                        isError: messageObject.bool("isError") ?? false
                    ), at: 0)
                } else {
                    var item = messageItem(id: baseID, entryID: entryID, role: role, text: text)
                    item.blocks = serverBlocks(object["text_blocks"])
                    items.insert(item, at: 0)
                }
            }
            return items
        default:
            return []
        }
    }

    /// text_blocks снимка → блоки чата (тот же разбор, что у сообщений).
    private static func serverBlocks(_ value: NewChatCore.JSONValue?) -> [ChatServerBlock]? {
        guard let value, case .array = value else { return nil }
        return ChatServerBlock.list(fromFoundation: value.foundationValue)
    }

    private static func messageItem(id: String, entryID: String?, role: String, text: String) -> SessionTimelineItem {
        SessionTimelineItem(
            id: id, entryID: entryID, kind: .message, role: role,
            title: roleTitle(role), text: text, isError: false
        )
    }

    private static func roleTitle(_ role: String) -> String {
        switch role {
        case "user": "Вы"
        case "assistant": "Помощник"
        case "toolResult": "Инструмент"
        default: role
        }
    }
}

private extension Dictionary where Key == String, Value == NewChatCore.JSONValue {
    func string(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }

    func object(_ key: String) -> [String: NewChatCore.JSONValue]? {
        guard case let .object(value)? = self[key] else { return nil }
        return value
    }

    func bool(_ key: String) -> Bool? {
        guard case let .bool(value)? = self[key] else { return nil }
        return value
    }

    var compactDescription: String {
        NewChatCore.JSONValue.object(self).compactDescription
    }
}

private extension NewChatCore.JSONValue {
    /// Короткое описание для строки активности. Глубина ограничена: аргументы
    /// инструментов бывают вложенными, а показывать всё равно нечего.
    var compactDescription: String { describe(depth: 0) }

    func describe(depth: Int) -> String {
        guard depth < 8 else { return "…" }
        switch self {
        case let .string(value): return value
        case let .number(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        case let .object(value):
            return value
                .map { "\($0.key): \($0.value.describe(depth: depth + 1))" }
                .sorted()
                .joined(separator: "\n")
        case let .array(value):
            return value.map { $0.describe(depth: depth + 1) }.joined(separator: "\n")
        case .null: return ""
        }
    }
}

extension NewChatCore.JSONValue {
    /// Значение для JSONSerialization.
    var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        case .array(let values): values.map(\.foundationValue)
        case .object(let values): values.mapValues(\.foundationValue)
        }
    }
}
