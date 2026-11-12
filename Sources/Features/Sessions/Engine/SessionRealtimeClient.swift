import Foundation
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
        guard socket == nil else { return }
        openSocket()
    }

    func disconnect() {
        wantsConnection = false
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
            let reconnected = reconnectAttempt > 0
            reconnectAttempt = 0
            connectionState = .connected
            if reconnected { await onReconnect?() }
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
        reconnectAttempt += 1
        let delay = min(pow(2, Double(reconnectAttempt - 1)), 30)
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
