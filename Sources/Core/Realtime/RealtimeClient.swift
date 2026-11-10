import Foundation
import Observation
import UIKit

/// Единственный канал реалтайма — WebSocket, SSE в проекте нет (spec/API.md §4).
/// `ws://192.168.1.110:3001/ws?token=<JWT-или-api_token>` — эндпоинт ВНЕ
/// префикса `/api`, токен в query (хендшейк-заголовки не всегда доступны
/// клиентским WS-библиотекам — тот же приём, что у веба).
///
/// `@MainActor`: всё состояние читает/пишет UI (сторы, индикатор соединения),
/// а `URLSessionWebSocketTask.receive` коллбэк приходит с произвольной
/// очереди — каждый такой коллбэк перепрыгивает на `@MainActor` явным
/// `Task`, вместо `@unchecked Sendable`/ручных блокировок.
@MainActor
@Observable
public final class RealtimeClient {
    public private(set) var isConnected = false
    private(set) var revisions = TaskRevisions()
    public private(set) var rolesRevision = 0
    public private(set) var jobsRevision = 0
    /// Растёт при событии сущности вне задачи (заметка, рутина,
    /// вложение). Экраны подписываются на неё и перечитывают себя.
    public private(set) var entityRevision = 0

    public var taskRevisions: [String: Int] { revisions.tasks }
    public var activityRevisions: [String: Int] { revisions.activity }
    /// Растёт на каждом подключении — для экранов ролей и работ, у которых
    /// нет дельты. Карточки задач смотрят на `staleRevision`.
    public var connectionRevision: Int { revisions.connection }
    public var staleRevision: Int { revisions.stale }

    public func revision(for taskID: String) -> Int {
        revisions.revision(for: taskID)
    }

    /// Итог догона после переподключения: изменившиеся id или `nil`, если
    /// дельты не было.
    func recordCatchUp(changedTaskIDs: Set<String>?) {
        revisions.catchUp(changedTaskIDs: changedTaskIDs)
    }

    /// Догон сущностей вне задачи (заметки, рутины, вложения) по курсору.
    ///
    /// События сокета в разрыв связи не доходят, поэтому после разрыва
    /// экраны заметок и рутин узнают об изменениях только отсюда: ревизия
    /// растёт, и они перечитывают себя.
    func recordEntityCatchUp() {
        entityRevision += 1
    }

    /// Invalidation events wake only affected screens; no screen polling timer.
    func record(_ event: RealtimeEvent) {
        switch event {
        case .connected: revisions.connected()
        case .taskChanged(let id), .taskDeleted(let id): revisions.taskChanged(id)
        case .taskCreated(let task), .taskUpdated(let task), .taskState(let task), .taskCompleted(let task):
            revisions.taskChanged(task.id, parent: task.parentId)
            // Списки ролей и работ перезагружаются по окну, а не на каждое
            // событие: во время работы агента события идут пачками, и каждый
            // экран уходил в сеть со своим запросом на каждое из них.
            scheduleCoalescedInvalidation()
        case .rolesChanged: rolesRevision += 1
        case .roleJobsChanged: jobsRevision += 1; rolesRevision += 1
        case .entityChanged: entityRevision += 1
        case .taskActivity(let id?, _): revisions.activityChanged(id)
        default: break
        }
    }

    /// Окно схлопывания: столько ждём, прежде чем разбудить экраны ролей и
    /// работ. Свежесть списка — не хуже половины секунды, запросов — в разы
    /// меньше. Состав ролей (`.rolesChanged`) ждать не должен: это редкое
    /// событие, и оно меняет список по-настоящему.
    private static let invalidationWindow = Duration.milliseconds(500)
    private var pendingRolesInvalidation = false
    private var pendingJobsInvalidation = false
    private var coalesceTask: Task<Void, Never>?

    private func scheduleCoalescedInvalidation() {
        pendingRolesInvalidation = true
        pendingJobsInvalidation = true
        guard coalesceTask == nil else { return }
        coalesceTask = Task { [weak self] in
            try? await ContinuousClock().sleep(for: Self.invalidationWindow)
            guard !Task.isCancelled else { return }
            self?.flushCoalescedInvalidation()
        }
    }

    private func flushCoalescedInvalidation() {
        coalesceTask = nil
        if pendingRolesInvalidation {
            rolesRevision += 1
            pendingRolesInvalidation = false
        }
        if pendingJobsInvalidation {
            jobsRevision += 1
            pendingJobsInvalidation = false
        }
    }

    /// На каждое разобранное событие — сторы подписываются здесь напрямую,
    /// без Combine/NotificationCenter (проще в @Observable-мире SwiftUI).
    /// НЕ `@Sendable` — весь класс уже `@MainActor`, замыкание вызывается
    /// строго оттуда же, лишнее требование только мешало бы захватывать
    /// обычные (не-Sendable) `@Observable`-сторы.
    public var onEvent: ((RealtimeEvent) -> Void)?
    /// Подписчики на события. Слот `onEvent` один, и его держит приложение
    /// (TaskStore), поэтому экранам нужен свой список: событие получают все
    /// подписчики, а снятие подписки никого не ломает. Без этого каждый экран
    /// шторки роли поднимал свой WebSocket — в журнале сервера это десятки
    /// переподключений в минуту.
    @ObservationIgnored private var observers: [UUID: (RealtimeEvent) -> Void] = [:]
    /// Ход шага карточки дельтами → привычный `.taskLive` для экранов.
    @ObservationIgnored private var taskLiveRouter = TaskLiveDeltaRouter()

    /// Подписаться на события. Возвращает токен подписки.
    @discardableResult
    public func addObserver(_ observer: @escaping (RealtimeEvent) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    /// Снять подписку. Чужой или уже снятый токен — не ошибка.
    public func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    /// Раздать событие: старый слот и новые подписчики.
    /// Внутренний метод — unit-тест проверяет доставку без сокета.
    func dispatchToSubscribers(_ event: RealtimeEvent) {
        onEvent?(event)
        for observer in observers.values { observer(event) }
    }
    /// Только на ПЕРЕподключение (не на первое) — spec §4.2: сервер не хранит
    /// очередь пропущенных событий за время разрыва, сторам нужно обновиться
    /// явным REST-запросом, а не ждать, что WS сам «досоединится».
    public var onReconnected: (() -> Void)?

    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var watchdogTask: Task<Void, Never>?
    private var lastTrafficAt = Date()
    private var hasConnectedBefore = false
    private var isStopping = true
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var patchCount = 0
    private var rawChatMessages = 0
    @ObservationIgnored private var authorizationRecoveryTask: Task<Void, Never>?
    private let allowsBackgroundConnection: Bool
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    private var wantsConnection = false
    @ObservationIgnored private var diagnosticSocketID: UUID?
    @ObservationIgnored private var diagnosticWatchdogID: UUID?

    private static let watchdogIntervalNs: UInt64 = 20_000_000_000
    /// Дольше этого без НИКАКОГО входящего трафика (включая keepalive `ping`)
    /// — считаем соединение мёртвым (spec §4.2: `OPEN`, но фактически мёртв
    /// после сна/блокировки устройства — `readyState` в этот момент не врёт,
    /// но и не отражает реальность, полагаться только на него нельзя).
    private static let staleThreshold: TimeInterval = 45

    public init(allowsBackgroundConnection: Bool = false) {
        self.allowsBackgroundConnection = allowsBackgroundConnection
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.allowsBackgroundConnection else { return }
                self.closeConnection()
            }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.wantsConnection else { return }
                self.connect()
            }
        })
    }

    public func connect() {
        wantsConnection = true
        guard allowsBackgroundConnection || UIApplication.shared.applicationState != .background else { return }
        guard isStopping else { return }
        isStopping = false
        openSocket()
        startWatchdog()
    }

    deinit {
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
        if let diagnosticSocketID { AppDiagnostics.shared.end(diagnosticSocketID) }
        if let diagnosticWatchdogID { AppDiagnostics.shared.end(diagnosticWatchdogID) }
    }

    public func disconnect() {
        wantsConnection = false
        closeConnection()
    }

    private func closeConnection() {
        if let diagnosticSocketID { AppDiagnostics.shared.end(diagnosticSocketID) }
        diagnosticSocketID = nil
        if let diagnosticWatchdogID { AppDiagnostics.shared.end(diagnosticWatchdogID) }
        diagnosticWatchdogID = nil
        isStopping = true
        reconnectTask?.cancel()
        reconnectTask = nil
        authorizationRecoveryTask?.cancel()
        authorizationRecoveryTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        // Отложенная инвалидация на разрыве связи не нужна: переподключение
        // и так поднимает `connectionRevision`, а по нему экраны перечитывают.
        coalesceTask?.cancel()
        coalesceTask = nil
        pendingRolesInvalidation = false
        pendingJobsInvalidation = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func openSocket() {
        guard let token = KeychainService.shared.token else { return }
        var components = URLComponents()
        components.scheme = "ws"
        components.host = APIClient.baseURL.host
        components.port = APIClient.baseURL.port
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }

        let newTask = session.webSocketTask(with: url)
        if let diagnosticSocketID { AppDiagnostics.shared.end(diagnosticSocketID) }
        diagnosticSocketID = AppDiagnostics.shared.begin(.socket)
        task = newTask
        newTask.resume()
        // Живой ход до телефона не доходит (10.11.2026): сервер пишет
        // `sent=1`, клиент не пишет ни одного `live:start`. Без причины
        // разрыва это не разобрать — пишем её в журнал клиента.
        ClientLog.shared.add("ws:open attempt=\(reconnectAttempt) token=\(KeychainService.shared.token == KeychainService.shared.deviceToken ? "device" : "session")")
        lastTrafficAt = Date()
        listen(on: newTask)
    }

    private func listen(on socketTask: URLSessionWebSocketTask) {
        socketTask.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                self.handleReceiveResult(result, task: socketTask)
            }
        }
    }

    private func handleReceiveResult(
        _ result: Result<URLSessionWebSocketTask.Message, Error>,
        task socketTask: URLSessionWebSocketTask
    ) {
        switch result {
        case .failure(let error):
            // Тот же гвард, что в success-ветке: watchdog при "зависшем" сокете
            // сам обнуляет `task` и запускает переподключение ДО того, как
            // старый `receive` вернёт failure — без проверки это второй,
            // лишний `handleDisconnect`/reconnect поверх уже открытого нового
            // сокета (дублирующиеся события, двойной onReconnected).
            guard task === socketTask else { return }
            ClientLog.shared.add("ws:fail attempt=\(reconnectAttempt) \(error.localizedDescription)")
            handleDisconnect()
        case .success(let message):
            guard task === socketTask else { return }
            AppDiagnostics.shared.increment(.messages)
            lastTrafficAt = Date()
            handle(message: message, task: socketTask)
            // Тот же сокет ещё актуален (не заменён переподключением) — читаем дальше.
            if task === socketTask {
                listen(on: socketTask)
            }
        }
    }

    /// Состояние соединения меняется отдельно от доставки событий.
    /// Внутренняя точка проверки протокола, без настоящей сети.
    func confirmConnection(for event: RealtimeEvent) {
        // Только серверный handshake подтверждает вход. Кадр error раньше
        // запускал onReconnected и сбрасывал backoff каждые 1,6 секунды.
        guard case .connected = event else { return }
        if !isConnected {
            ClientLog.shared.add("ws:live ok attempt=\(reconnectAttempt)")
            isConnected = true
            if hasConnectedBefore {
                // За разрыв дельты могли потеряться — прогоны на старые снимки.
                taskLiveRouter.reset()
                onReconnected?()
            }
            hasConnectedBefore = true
            reconnectAttempt = 0
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message, task socketTask: URLSessionWebSocketTask) {
        guard case .string(let text) = message, let data = text.data(using: .utf8) else { return }
        // Самый дешёвый факт приёма, без разбора: дошли ли чатовые байты.
        if text.contains("\"chats:") {
            rawChatMessages += 1
            if rawChatMessages <= 3 { ClientLog.shared.add("rx:chat-raw#\(rawChatMessages) len=\(text.count)") }
        }
        // В фоне этот сокет держится только ради карточки Live Activity, а она
        // живёт на событиях `task:*`. Живой ход чата и задачи в фоне не видит
        // никто, а весит он больше всего: телефон разбирал весь выросший текст
        // и получал watchdog `0x8BADF00D` в фоне (отчёты 03–28.10.2026, до
        // 48 с CPU за 10-секундное окно). Отбрасываем по одному дешёвому полю.
        if allowsBackgroundConnection, UIApplication.shared.applicationState != .active,
           let type = RealtimeEvent.typeName(of: data), RealtimeEvent.isBackgroundIrrelevant(type) {
            return
        }
        guard let event = RealtimeEvent.parse(data) else {
            // Разбор не удался — событие есть, но в типы не легло: без этой
            // строки такая потеря невидима (в журнале сервера оно «отправлено»).
            if let type = RealtimeEvent.typeName(of: data), type.contains("chat") {
                ClientLog.shared.add("rx-fail:\(type)")
            }
            return
        }
        // Ход роли по сокету не доходил до экрана (10.11.2026): сервер писал
        // `sent=1`, а в журнале клиента не было ни одного `live:start`.
        // Пишем сами факты приёма: дошли ли чатовые события вообще.
        if let type = RealtimeEvent.typeName(of: data), !type.hasSuffix(":patch") {
            ClientLog.shared.add("rx:\(type)")
        } else if RealtimeEvent.typeName(of: data) != nil {
            patchCount += 1
            if patchCount <= 3 || patchCount % 50 == 0 {
                ClientLog.shared.add("rx:patch#\(patchCount)")
            }
        }
        if case .serverError(let message) = event,
           message == "unauthorized" || message == "device_revoked" {
            recoverAuthorization(revoked: message == "device_revoked")
            return
        }
        confirmConnection(for: event)
        record(event)
        if case .ping = event {
            // Keepalive — сервер шлёт ping, клиент обязан ответить pong (spec §4).
            socketTask.send(.string("{\"type\":\"pong\"}")) { _ in }
        }
        if case .deviceOp(let request) = event {
            // Команда сервера телефону: исполнить через EventKit и ответить
            // на тот же opId. Ответ уходит по тому же сокету, по которому
            // пришла команда.
            Task { @MainActor in
                let answer = await DeviceOpsChannel.shared.resultMessage(for: request)
                socketTask.send(.string(answer)) { _ in }
            }
        }
        switch event {
        case .taskLiveDelta(let delta):
            if case .show(let state, let complete) = taskLiveRouter.route(delta) {
                dispatchToSubscribers(.taskLive(TaskLiveTurn(state: state, complete: complete)))
            }
            return
        case .taskLive(let turn) where taskLiveRouter.routeSnapshot(runID: turn.runID) == .drop:
            return
        default:
            break
        }
        dispatchToSubscribers(event)
    }

    /// HTTP дома может пройти через LAN-вход даже с недействительным JWT;
    /// WebSocket требует действующий токен. Обновляем его штатным LAN-входом
    /// один раз после отказа, не принимая отказ за восстановление соединения.
    private func recoverAuthorization(revoked: Bool) {
        closeConnection()
        if revoked {
            rejectAuthorization()
            return
        }
        authorizationRecoveryTask = Task { [weak self] in
            do {
                let response = try await APIClient().lanLogin()
                guard !Task.isCancelled, let self, self.wantsConnection else { return }
                KeychainService.shared.token = response.token
                self.authorizationRecoveryTask = nil
                self.connect()
            } catch {
                guard !Task.isCancelled, let self else { return }
                ClientLog.shared.add("ws:auth-fail \(error.localizedDescription)")
                self.authorizationRecoveryTask = nil
                self.rejectAuthorization()
            }
        }
    }

    private func rejectAuthorization() {
        disconnect()
        KeychainService.shared.token = nil
        NotificationCenter.default.post(name: .taskFlowUnauthorized, object: nil)
    }

    private func handleDisconnect() {
        guard !isStopping else { return }
        if let diagnosticSocketID { AppDiagnostics.shared.end(diagnosticSocketID) }
        diagnosticSocketID = nil
        isConnected = false
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isStopping else { return }
        reconnectAttempt += 1
        AppDiagnostics.shared.increment(.reconnects)
        // Экспоненциальный бэкофф, потолок 30с — не долбить сервер при долгом офлайне.
        let delaySeconds = min(30.0, pow(1.6, Double(reconnectAttempt)))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000)) } catch { return }
            guard let self else { return }
            await MainActor.run {
                guard !self.isStopping else { return }
                self.openSocket()
            }
        }
    }

    private func startWatchdog() {
        if let diagnosticWatchdogID { AppDiagnostics.shared.end(diagnosticWatchdogID) }
        diagnosticWatchdogID = AppDiagnostics.shared.begin(.watchdog)
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.watchdogIntervalNs)
                guard !Task.isCancelled, let self else { return }
                AppDiagnostics.shared.increment(.watchdogChecks)
                await MainActor.run {
                    guard !self.isStopping else { return }
                    if Date().timeIntervalSince(self.lastTrafficAt) > Self.staleThreshold {
                        // Обнулить `task` ДО cancel — иначе отменённый `receive`
                        // придёт с failure чуть позже и (совпав по `task === socketTask`
                        // в старом коде) вызовет второй handleDisconnect/reconnect
                        // поверх уже переоткрытого сокета. См. guard в failure-ветке выше.
                        let staleTask = self.task
                        self.task = nil
                        // 1006 (`abnormalClosure`) по протоколу в кадре закрытия
                        // слать нельзя — сервер отвечал ошибкой WS_ERR_INVALID_CLOSE_CODE.
                        staleTask?.cancel(with: .goingAway, reason: nil)
                        self.handleDisconnect()
                    }
                }
            }
        }
    }
}
