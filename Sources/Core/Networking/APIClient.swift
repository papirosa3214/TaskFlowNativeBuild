import Foundation

/// HTTP-клиент TaskFlow поверх `URLSession` (async/await) — spec/API.md §1-2.
///
/// Правила контракта, зашитые здесь:
/// - Базовый адрес `http://192.168.1.110:3001`, JSON-эндпоинты — с префиксом
///   `/api`; исключение — `/ws` (реалтайм, `RealtimeClient`) и загрузка/
///   скачивание сырых байтов, у которых свой путь без общего префикса тела.
/// - Один и тот же заголовок `Authorization: Bearer <значение>` для JWT и
///   api_token — сервер сам разбирает, что прислано (§2). Токен читается из
///   `KeychainService` на каждый запрос, а не хранится в клиенте — так
///   `APIClient` не тянет за собой состояние сессии/DI-цикл с `SessionStore`.
/// - Ошибка сервера всегда `{ "error": "..." }` при не-2xx (§1) — разбирается
///   в `APIError`. На 401 клиент чистит токен и рассылает уведомление, чтобы
///   `SessionStore` мог сразу разлогинить (§2.2: LAN-релогин веба нативу не
///   подходит, только «на выход»).
public final class APIClient: Sendable {
    public static let baseURL = URL(string: "http://192.168.1.110:3001")!

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - JSON-запросы

    /// Тело — любой `Encodable` (обычно `[String: JSONValue]` для PATCH,
    /// строго типизированная структура для POST, см. `Encodable`-обёртки в
    /// доменных `APIClient+*.swift`).
    @discardableResult
    public func request<Response: Decodable>(
        _ method: HTTPMethodKind,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws -> Response {
        let request = try buildRequest(method: method, path: path, query: query, body: body)
        let (data, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: data, request: request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Вариант без ожидаемого тела ответа (сервер отвечает пустым телом) —
    /// на практике в этом API не встречен (везде минимум `{ok:true}`), но
    /// оставлен для полноты интерфейса.
    public func requestVoid(
        _ method: HTTPMethodKind,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws {
        let request = try buildRequest(method: method, path: path, query: query, body: body)
        let (data, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: data, request: request)
    }

    private func buildRequest(
        method: HTTPMethodKind,
        path: String,
        query: [URLQueryItem],
        body: (any Encodable)?
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("/api" + path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        // Признак «это приложение, а не скрипт»: по нему сервер пускает вход
        // без пароля из домашней сети (`looksLikeBrowser` в server/src/auth.ts).
        // Браузер там опознаётся по своим заголовкам, у нативного клиента их нет.
        request.setValue("ios-native", forHTTPHeaderField: "X-TaskFlow-Client")
        if let token = KeychainService.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }
        return request
    }

    // MARK: - Сырые байты (вложения/аватарки/аудио — spec §1, §5.10, §5.12)

    /// Загрузка файла сырыми байтами, БЕЗ multipart: тело = сам файл,
    /// `Content-Type` = реальный MIME, имя — в query `?name=`.
    @discardableResult
    public func uploadRaw<Response: Decodable>(
        path: String,
        query: [URLQueryItem],
        data: Data,
        mime: String
    ) async throws -> Response {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("/api" + path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidResponse }
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethodKind.post.rawValue
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        if let token = KeychainService.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = data

        let (responseData, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: responseData, request: request)
        do {
            return try decoder.decode(Response.self, from: responseData)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Скачивание файла — сырые байты. `GET /attachments/:id` требует
    /// `Authorization`, поэтому НЕ годится напрямую в `AsyncImage(url:)`
    /// (тот не умеет слать заголовки) — вызывающая сторона сама решает, что
    /// делать с байтами (превью, сохранение, показ через `UIImage(data:)`).
    /// `path` — полный путь ОТ `/api` (например `/attachments/\(id)`).
    public func downloadRaw(path: String) async throws -> Data {
        guard let url = URL(string: Self.baseURL.absoluteString + "/api" + path) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        if let token = KeychainService.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, http) = try await send(request)
        try Self.throwIfError(status: http.statusCode, data: data, request: request)
        return data
    }

    /// `GET /avatars/:name` — единственный ПУБЛИЧНЫЙ файловый эндпоинт (без
    /// авторизации, spec §5.10), поэтому обычному `AsyncImage(url:)` он
    /// годится напрямую — возвращаем готовый `URL`, без обёртки в запрос.
    public static func publicAvatarURL(name: String) -> URL {
        baseURL.appendingPathComponent("/api/avatars/\(name)")
    }

    // MARK: - Транспорт

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    private static func throwIfError(status: Int, data: Data, request: URLRequest? = nil) throws {
        guard !(200...299).contains(status) else { return }
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        let raw = body?.bestMessage ?? "Сервер ответил кодом \(status)"
        switch status {
        case 401:
            KeychainService.shared.token = nil
            NotificationCenter.default.post(name: .taskFlowUnauthorized, object: nil)
            throw APIError.unauthorized(message: raw)
        case 403:
            throw APIError.forbidden(message: raw)
        case 404:
            // Fastify так отвечает, когда маршрута у него просто нет: с
            // записями это не связано вообще, чинить надо сервер или клиент.
            if raw.contains("Route"), raw.localizedCaseInsensitiveContains("not found") {
                let what = Self.describe(request)
                throw APIError.routeMissing(message: what.isEmpty
                    ? "Сервер не знает такого запроса — похоже, приложение новее сервера"
                    : "Сервер не знает такого запроса: \(what). Похоже, приложение новее сервера")
            }
            throw APIError.notFound(message: Self.notFoundMessage(raw: raw, request: request))
        case 409:
            throw APIError.conflict(message: raw)
        default:
            throw APIError.server(status: status, message: raw)
        }
    }

    /// 404 у сервера означает три разные вещи, и раньше все три показывались
    /// одинаково — «Не найдено или нет доступа к этой записи». Владелец
    /// 15.09.2026 на это и указал: «пишет, что она удалена, но она не
    /// удалена». Теперь причина называется своим именем, а к ней добавляется
    /// упавший запрос — иначе непонятно, что именно чинить.
    private static func notFoundMessage(raw: String, request: URLRequest?) -> String {
        let what = describe(request)
        // Осмысленный ответ сервера всегда информативнее нашего текста.
        if raw.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil { return raw }
        return what.isEmpty
            ? "Запись не найдена или недоступна"
            : "Запись не найдена или недоступна (\(what))"
    }

    /// «PATCH /api/tasks/1234» — чтобы по баннеру было видно, что упало.
    private static func describe(_ request: URLRequest?) -> String {
        guard let request, let path = request.url?.path else { return "" }
        let method = request.httpMethod ?? "GET"
        return "\(method) \(path)"
    }
}

public enum HTTPMethodKind: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

/// Стирает конкретный тип `Encodable`-тела до однородного значения, которое
/// можно передать в `JSONEncoder.encode` без дженерика на уровне вызова
/// (нужно, потому что `body: (any Encodable)?` — экзистенциал, а
/// `JSONEncoder.encode` дженерик по конкретному типу).
private struct AnyEncodable: Encodable {
    private let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

public extension Notification.Name {
    /// Шлётся `APIClient` на любой 401 — `SessionStore` подписан и сразу
    /// разлогинивает (spec §2.2).
    static let taskFlowUnauthorized = Notification.Name("TaskFlowUnauthorized")
}
