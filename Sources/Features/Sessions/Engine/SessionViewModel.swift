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
            let id = "live-\(index)-\(message.role)"
            if message.role == "user" { return .user(id: id, text: message.text) }
            if message.role == "assistant", liveTurn.isEmpty, !message.text.isEmpty {
                return .reply(id: id, text: message.text, blocks: nil)
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
        guard let id = activeSessionID,
              let response = try? await apiClient.snapshot(sessionID: id) else { return }
        installSnapshot(response.session)
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
        let requestID = UUID().uuidString
        do {
            _ = try await apiClient.abort(
                sessionID: sessionID,
                request: AbortSessionRequest(requestId: requestID)
            )
        } catch {
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
        recordActivity(event)
        // Повтор уже принятого куска (после переподключения сервер может
        // прислать его снова) в живой ход не пишем — иначе слова двоятся.
        let isNew = !state.seenCursors.contains(event.cursor)
        if isNew, event.sessionId == activeSessionID {
            if event.type == "agent_start" { liveTurnHasGaps = false }
            liveTurn.apply(type: event.type, payload: event.payload, sessionID: event.sessionId)
        }
        SessionReducer.apply(event, to: &state)
        if event.sessionId == activeSessionID, event.type == "agent_settled" {
            Task { await refreshSnapshot() }
        } else if event.sessionId != activeSessionID, event.type == "agent_settled" {
            Task { await refreshSessions() }
        }
    }

    private func recoverAfterReconnect() async {
        guard let sessionID = activeSessionID else { return }
        do {
            if let cursor = state.lastCursor {
                let payload = try await apiClient.events(sessionID: sessionID, after: cursor)
                // Догнанные куски — и в живой ход: раньше они шли только в
                // состояние, и на экране в ответе пропадали слова (владелец
                // 13.11.2026: «какие-то слова не допечатываются»).
                ClientLog.shared.add("session=\(sessionID) recover events=\(payload.events.count) reset=\(payload.resetRequired)")
                if payload.resetRequired, !liveTurn.isEmpty { liveTurnHasGaps = true }
                if !payload.resetRequired {
                    for event in payload.events where !state.seenCursors.contains(event.cursor) && event.sessionId == sessionID {
                        liveTurn.apply(type: event.type, payload: event.payload, sessionID: sessionID)
                    }
                }
                SessionReducer.apply(payload, to: &state)
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
        do {
            let response = try await apiClient.snapshot(sessionID: sessionID)
            installSnapshot(response.session, preservingCursor: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSessions() async {
        do {
            sessions = try await apiClient.listSessions().sessions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installSnapshot(_ snapshot: SessionSnapshot, preservingCursor: Bool = false) {
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
        liveTurn.bind(sessionID: snapshot.id)
        // Ход закончен — его шаги уже в записях снимка. Напечатанный ход
        // остаётся на экране как есть, без подмены записями снимка (владелец
        // 13.11.2026: «если он уже напечатался — итоговый ответ не нужен»);
        // сбрасывается на следующем `agent_start`. Если в ходе дыра — берём снимок.
        if !snapshot.isStreaming, liveTurnHasGaps {
            liveTurn.reset()
            liveTurnHasGaps = false
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
