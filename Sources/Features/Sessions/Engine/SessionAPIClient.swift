import Foundation
import NewChatCore

struct AuthenticatedUser: Equatable, Sendable, Identifiable, JSONValueDecodable {
    let id: String
    let name: String
    let email: String?

    init(id: String, name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }

    init?(json: NewChatCore.JSONValue) {
        guard let id = json["id"]?.stringValue else { return nil }
        self.init(
            id: id,
            name: json["name"]?.stringValue ?? id,
            email: json["email"]?.stringValue
        )
    }
}

struct AuthenticationResponse: Sendable, JSONValueDecodable {
    let token: String
    let user: AuthenticatedUser

    init(token: String, user: AuthenticatedUser) {
        self.token = token
        self.user = user
    }

    init?(json: NewChatCore.JSONValue) {
        guard let token = json["token"]?.stringValue,
              let user = json["user"].flatMap(AuthenticatedUser.init(json:)) else { return nil }
        self.init(token: token, user: user)
    }
}

struct SessionMutationResponse: Sendable, JSONValueDecodable {
    let requestId: String
    let session: SessionSnapshot

    init(requestId: String, session: SessionSnapshot) {
        self.requestId = requestId
        self.session = session
    }

    init?(json: NewChatCore.JSONValue) {
        guard let requestId = json["requestId"]?.stringValue,
              let session = json["session"].flatMap(SessionSnapshot.init(json:)) else { return nil }
        self.init(requestId: requestId, session: session)
    }
}

enum SessionAPIError: LocalizedError, Equatable {
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Сервер вернул некорректный ответ."
        case let .server(_, message):
            return message
        case let .decoding(message):
            return "Не удалось разобрать ответ сервера: \(message)"
        }
    }
}

/// Клиент сессий владельца (`/api/sessions`) — перенесён из прототипа
/// NewChatTF (владелец 12.11.2026: «из помощника делать не роль, а просто
/// обычные сессии»). Адрес и токен — общие с TaskFlow (`APIClient.baseURL`,
/// `KeychainService`); истёкший токен обновляется домашним входом на месте,
/// и запрос повторяется — набранный текст не теряется.
final class SessionAPIClient: @unchecked Sendable {
    static let taskFlowBaseURL = APIClient.baseURL

    private let baseURL: URL
    private let tokenStore: any SessionTokenStoring
    private let session: URLSession
    private let encoder = JSONEncoder()
    /// Только для плоских ответов каталога провайдеров. Состояние сессии
    /// разбирает \`NewChatCore.JSONValue.parse\`: у него нет ни рекурсии, ни лимита 512
    /// вложенных контейнеров, из-за которых сессия не открывалась.
    private let decoder = JSONDecoder()
    private let authLock = NSLock()
    private var reauthInFlight: Task<Bool, Never>?

    init(
        baseURL: URL = SessionAPIClient.taskFlowBaseURL,
        tokenStore: any SessionTokenStoring = TaskFlowSessionToken.shared,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Тихий вход из домашней сети. Ничего не спрашивает у человека.
    func lanLogin() async throws -> AuthenticationResponse {
        try await request(method: "POST", path: "/api/auth/lan", body: [String: String]())
    }

    /// Обновить токен без участия человека. Параллельные 401 ждут один запрос.
    func silentReauthenticate() async -> Bool {
        let task: Task<Bool, Never>
        authLock.lock()
        if let existing = reauthInFlight {
            authLock.unlock()
            return await existing.value
        }
        task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            defer { self.finishReauth() }
            do {
                // Через perform, а не через request: 401 здесь ожидаем и
                // повторять сам себя повторный вход не должен.
                let data = try await self.perform(
                    method: "POST", path: "/api/auth/lan", body: [String: String]()
                )
                guard let response = AuthenticationResponse(json: try NewChatCore.JSONValue.parse(data)) else {
                    throw SessionAPIError.decoding("В ответе входа нет токена.")
                }
                self.tokenStore.token = response.token
                return true
            } catch {
                return false
            }
        }
        reauthInFlight = task
        authLock.unlock()
        return await task.value
    }

    private func finishReauth() {
        authLock.lock()
        reauthInFlight = nil
        authLock.unlock()
    }

    func currentUser() async throws -> AuthenticatedUser {
        struct Response: JSONValueDecodable {
            let user: AuthenticatedUser
            init?(json: NewChatCore.JSONValue) {
                guard let user = json["user"].flatMap(AuthenticatedUser.init(json:)) else { return nil }
                self.user = user
            }
        }
        let response: Response = try await request(method: "GET", path: "/api/auth/me")
        return response.user
    }

    func openRoot() async throws -> SessionResponse {
        try await request(method: "POST", path: "/api/sessions/root")
    }

    /// Новая сессия разговора (`POST /api/sessions`, идемпотентно по requestId).
    func createSession(requestID: String = UUID().uuidString) async throws -> SessionResponse {
        try await request(method: "POST", path: "/api/sessions", body: ["requestId": requestID])
    }

    /// Метки сессии: название, проект, закрепление, архив (`PATCH /api/sessions/:id`).
    func patchSession(id: String, _ patch: SessionMetaPatch) async throws {
        let _: SessionAck = try await request(method: "PATCH", path: "/api/sessions/\(id)", body: patch)
    }

    /// Замер контекста сессии — в форме замера чата (`ChatContextSnapshot`).
    func context(sessionID: String) async throws -> ChatContextSnapshot {
        struct Envelope: Decodable { let context: ChatContextSnapshot }
        let response: Envelope = try await requestDecoding(method: "GET", path: "/api/sessions/\(sessionID)/context")
        return response.context
    }

    func listSessions() async throws -> SessionListResponse {
        try await request(method: "GET", path: "/api/sessions")
    }

    func snapshot(sessionID: String) async throws -> SessionResponse {
        try await request(method: "GET", path: "/api/sessions/\(sessionID)")
    }

    /// Список дел агента Pi в сессии — готовым ответом сервера: пункты, их
    /// статусы и счётчики считает сервер, клиент только показывает.
    func todos(sessionID: String) async throws -> SessionTodosResponse {
        try await requestDecoding(method: "GET", path: "/api/sessions/\(sessionID)/todos")
    }

    func events(sessionID: String, after cursor: String?) async throws -> SessionReconnectPayload {
        try await request(
            method: "GET",
            path: "/api/sessions/\(sessionID)/events",
            queryItems: cursor.map { [URLQueryItem(name: "after", value: $0)] } ?? []
        )
    }

    func prompt(sessionID: String, request body: PromptSessionRequest) async throws -> CommandAcknowledgement {
        try await request(method: "POST", path: "/api/sessions/\(sessionID)/prompt", body: body, timeout: 120)
    }

    func abort(sessionID: String, request body: AbortSessionRequest) async throws -> CommandAcknowledgement {
        try await request(method: "POST", path: "/api/sessions/\(sessionID)/abort", body: body)
    }

    func branch(sessionID: String, request body: SessionEntryCommandRequest) async throws -> SessionMutationResponse {
        try await request(method: "POST", path: "/api/sessions/\(sessionID)/branch", body: body)
    }

    func fork(sessionID: String, request body: SessionEntryCommandRequest) async throws -> SessionMutationResponse {
        try await request(method: "POST", path: "/api/sessions/\(sessionID)/fork", body: body)
    }

    // MARK: - Модель сессии (каталог моделей — `APIClient.runtimeModels`)

    /// `PUT /api/sessions/:id/model` — переключение модели сессии.
    func setSessionModel(
        sessionID: String,
        request body: SetSessionModelRequest
    ) async throws -> SessionMutationResponse {
        try await request(method: "PUT", path: "/api/sessions/\(sessionID)/model", body: body, timeout: 60)
    }

    // MARK: - Транспорт

    private func request<Response: JSONValueDecodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        timeout: TimeInterval = 20
    ) async throws -> Response {
        let data = try await dataWithReauthentication(
            method: method, path: path, queryItems: queryItems, body: body, timeout: timeout
        )
        do {
            let value = try NewChatCore.JSONValue.parse(data)
            guard let response = Response(json: value) else {
                throw SessionAPIError.decoding("В ответе нет обязательных полей.")
            }
            return response
        } catch let error as SessionAPIError {
            throw error
        } catch {
            throw SessionAPIError.decoding(error.localizedDescription)
        }
    }

    private func requestDecoding<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        timeout: TimeInterval = 20
    ) async throws -> Response {
        let data = try await dataWithReauthentication(
            method: method, path: path, queryItems: queryItems, body: body, timeout: timeout
        )
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SessionAPIError.decoding(error.localizedDescription)
        }
    }

    /// 401 не выбрасывает из приложения: тихо входим и повторяем запрос.
    private func dataWithReauthentication(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: (any Encodable)?,
        timeout: TimeInterval
    ) async throws -> Data {
        do {
            return try await perform(
                method: method, path: path, queryItems: queryItems, body: body, timeout: timeout
            )
        } catch let SessionAPIError.server(status, _) where status == 401 {
            guard await silentReauthenticate() else {
                throw SessionAPIError.server(status: 401, message: "Сервер не пустил: нет доступа из этой сети.")
            }
            return try await perform(
                method: method, path: path, queryItems: queryItems, body: body, timeout: timeout
            )
        }
    }

    private func perform(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        timeout: TimeInterval = 20
    ) async throws -> Data {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SessionAPIError.invalidResponse }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios-native", forHTTPHeaderField: "X-TaskFlow-Client")
        if let token = tokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(SessionAnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SessionAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? NewChatCore.JSONValue.parse(data))?["error"]?.stringValue
                ?? "Ошибка сервера (\(http.statusCode))."
            throw SessionAPIError.server(status: http.statusCode, message: message)
        }
        return data
    }
}

private struct SessionAnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

/// Ответ без нужных клиенту полей — любой JSON-объект.
private struct SessionAck: JSONValueDecodable {
    init?(json: NewChatCore.JSONValue) {}
}

/// Тело `PATCH /api/sessions/:id`: уходят только заданные поля; проект
/// снимается явным `null`.
enum SessionMetaPatch: Encodable {
    case title(String)
    case project(String?)
    case pinned(Bool)
    case archived(Bool)

    private struct Key: CodingKey {
        var stringValue: String
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .title(let value): try container.encode(value, forKey: Key("title"))
        case .project(let value?): try container.encode(value, forKey: Key("project_id"))
        case .project(nil): try container.encodeNil(forKey: Key("project_id"))
        case .pinned(let value): try container.encode(value, forKey: Key("pinned"))
        case .archived(let value): try container.encode(value, forKey: Key("archived"))
        }
    }
}
