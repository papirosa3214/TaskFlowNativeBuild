import Foundation
import UIKit
import NewChatCore
import Observation

@MainActor
@Observable
final class SessionRealtimeClient {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    private(set) var connectionState: ConnectionState = .disconnected

    private let baseURL: URL
    private let tokenStore: any SessionTokenStoring
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var wantsConnection = false
    private var reconnectAttempt = 0
    /// Сокет уже хоть раз был на связи: любое следующее «connected» —
    /// переподключение, после которого дотягиваем пропущенные события.
    /// Раньше смотрели на `reconnectAttempt`, а повторный вход его обнулял —
    /// и пропущенное не дотягивалось (владелец 13.11.2026: «слова не
    /// допечатываются»).
    private var hasConnectedOnce = false
    private var droppedAt: Date?
    private var foregroundObserver: NSObjectProtocol?
    private var onEvent: (@MainActor (SessionEventEnvelope) -> Void)?
    private var onReconnect: (@MainActor () async -> Void)?

    /// Тихий вход при отказе сокета. Возвращает true, если токен обновлён.
    /// 30.11.2026: отказ авторизации больше не выбрасывает из чата — сначала
    /// пробуем войти заново и переподключиться.
    var silentAuth: (@MainActor () async -> Bool)?

    init(
        baseURL: URL = SessionAPIClient.taskFlowBaseURL,
        tokenStore: any SessionTokenStoring = TaskFlowSessionToken.shared,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    func connect(
        onEvent: @escaping @MainActor (SessionEventEnvelope) -> Void,
        onReconnect: @escaping @MainActor () async -> Void
    ) {
        self.onEvent = onEvent
        self.onReconnect = onReconnect
        wantsConnection = true
        if foregroundObserver == nil {
            // Вернулись на экран — переподключаемся сразу, не дожидаясь паузы.
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reconnectNowIfNeeded() }
            }
        }
        guard socket == nil else { return }
        openSocket()
    }

    private func reconnectNowIfNeeded() {
        guard wantsConnection, connectionState != .connected else { return }
        ClientLog.shared.add("session.ws foreground:reconnect")
        reconnectTask?.cancel()
        reconnectTask = nil
        closeSocket()
        openSocket()
    }

    func disconnect() {
        wantsConnection = false
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        foregroundObserver = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        closeSocket()
        connectionState = .disconnected
    }

    private func openSocket() {
        guard wantsConnection else {
            connectionState = .disconnected
            return
        }
        // Домашняя сеть пускает REST и без токена, но сокету токен нужен.
        // Берём его тихо, без экранов входа.
        guard let token = tokenStore.token else {
            connectionState = .connecting
            Task { [weak self] in
                guard let self else { return }
                if await self.silentAuth?() == true {
                    self.openSocket()
                } else {
                    self.handleDisconnect()
                }
            }
            return
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/ws"
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else { return }

        connectionState = .connecting
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        receiveTask = Task { [weak self, weak socket] in
            guard let self, let socket else { return }
            await self.receiveLoop(from: socket)
        }
    }

    private func receiveLoop(from socket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard self.socket === socket else { return }
                switch message {
                case let .string(text):
                    await handle(Data(text.utf8), socket: socket)
                case let .data(data):
                    await handle(data, socket: socket)
                @unknown default:
                    break
                }
            }
        } catch {
            guard self.socket === socket else { return }
            handleDisconnect()
        }
    }

    private func handle(_ data: Data, socket: URLSessionWebSocketTask) async {
        guard let frame = RealtimeFrame(data: data) else { return }
        switch frame.type {
        case "connected":
            let reconnected = hasConnectedOnce
            hasConnectedOnce = true
            reconnectAttempt = 0
            connectionState = .connected
            if reconnected {
                let gap = droppedAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "?"
                ClientLog.shared.add("session.ws reconnected gap=\(gap)s")
                droppedAt = nil
                await onReconnect?()
            }
        case "ping":
            try? await socket.send(.string(#"{"type":"pong"}"#))
        case "session:event":
            if let event = frame.event { onEvent?(event) }
        case "error":
            if frame.error == "unauthorized" {
                await reauthenticate()
            }
        default:
            break
        }
    }

    private func reauthenticate() async {
        closeSocket()
        connectionState = .disconnected
        guard wantsConnection else { return }
        reconnectAttempt = 0
        if await silentAuth?() == true {
            openSocket()
        } else {
            handleDisconnect()
        }
    }

    private func handleDisconnect() {
        closeSocket()
        guard wantsConnection else { return }
        connectionState = .disconnected
        if droppedAt == nil { droppedAt = Date() }
        reconnectAttempt += 1
        // Первая попытка — сразу: короткий обрыв не должен быть заметен.
        let delay = reconnectAttempt == 1 ? 0 : min(pow(2, Double(reconnectAttempt - 2)), 30)
        ClientLog.shared.add("session.ws dropped attempt=\(reconnectAttempt) retryIn=\(delay)s")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.openSocket()
        }
    }

    private func closeSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }
}

/// Кадр сокета. Разбирается тем же парсером, что и REST: сообщение может
/// нести payload произвольной глубины.
private struct RealtimeFrame {
    let type: String
    let event: SessionEventEnvelope?
    let error: String?

    init?(data: Data) {
        guard let json = try? NewChatCore.JSONValue.parse(data), let type = json["type"]?.stringValue else {
            return nil
        }
        self.type = type
        self.event = json["event"].flatMap(SessionEventEnvelope.init(json:))
        self.error = json["error"]?.stringValue
    }
}
