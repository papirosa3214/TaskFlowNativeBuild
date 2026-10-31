import Foundation

/// Руччки синхронизации для локальной базы.
///
/// Отдельный файл, а не дописывание `APIClient+RoleChats.swift`: здесь
/// нужны СЫРЫЕ тела (их кладём в базу как есть) и отпечатки — обычные
/// `roleChats()`/`roleChatMessages()` декодируют модель и теряют тело.
public extension APIClient {
    /// Таймаут запросов синхронизации — 10 секунд. Дольше ждать нечего:
    /// локальная база уже показана, а зависший запрос только держит
    /// соединение.
    static let localSyncTimeout: TimeInterval = 10

    /// Конверт списка чатов: сервер отдаёт `{"chats":[…]}`.
    ///
    /// Свой, а не тот, что в `APIClient+RoleChats.swift`: там он приватный
    /// и достать его из другого файла нельзя, а синхронизации нужно
    /// разобрать сырое тело самому.
    public struct RoleChatsSyncEnvelope: Decodable {
        public let chats: [RoleChat]
    }

    /// Конверт истории сообщений: сервер отдаёт `{"messages":[…]}`.
    public struct RoleChatMessagesSyncEnvelope: Decodable {
        public let messages: [RoleChatMessage]
    }

    /// Ответ списка чатов вместе с отпечатком.
    struct RoleChatsSyncResult {
        /// Сырое тело ответа. При 304 — пустое.
        public let data: Data
        /// Сервер ответил «не менялось» (304) — тело не присылали.
        public let notModified: Bool
        /// Отпечаток тела: присылаем его обратно, и сервер отвечает 304,
        /// пока список не менялся. Пустой отпечаток — сервер его не шлёт
        /// (старый сервер), тогда каждый раз приходит полный список.
        public let etag: String?
    }

    /// Страница сообщений чата.
    struct RoleChatMessagesPage {
        /// Сырое тело ответа.
        public let data: Data
        /// Есть ли ещё сообщения в направлении запроса.
        /// `nil` — сервер такого признака не отдаёт (старый сервер): тогда
        /// пришёл весь чат целиком и догружать по частям нельзя.
        public let hasMore: Bool?
    }

    /// `GET /api/chats` с отпечатком: сервер отвечает 304, если список
    /// не менялся, и телефон не качает его заново.
    ///
    /// `etag` — отпечаток из прошлого раза (лежит в локальной базе, поэтому
    /// переживает перезапуск приложения). `nil` — отпечатка нет, спрашиваем
    /// как обычно.
    func roleChatsSync(includeClosed: Bool = false, etag: String?) async throws -> RoleChatsSyncResult {
        var query: [URLQueryItem] = []
        if includeClosed { query.append(URLQueryItem(name: "include_closed", value: "1")) }
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = etag }
        let (data, http) = try await requestRaw(
            .get, "/chats",
            query: query,
            timeout: Self.localSyncTimeout,
            acceptedErrorStatuses: [304],
            headers: headers
        )
        if http.statusCode == 304 {
            return RoleChatsSyncResult(data: Data(), notModified: true, etag: http.value(forHTTPHeaderField: "ETag"))
        }
        return RoleChatsSyncResult(
            data: data,
            notModified: false,
            etag: http.value(forHTTPHeaderField: "ETag")
        )
    }

    /// `GET /api/chats/:id/messages` с постраничной выдачей.
    ///
    /// - `after` — только сообщения НОВЕЕ курсора (догрузка вниз).
    /// - `before` — только сообщения СТАРЕЕ курсора (догрузка вверх).
    /// - `limit` — сколько максимум (сервер ограничивает 200).
    ///
    /// Старый сервер эти параметры не понимает и отдаёт весь чат целиком —
    /// это не сломает клиент: лишние сообщения просто перезапишутся в базе
    /// теми же id. Признак «есть ещё» тогда тоже не приходит, и клиент
    /// понимает, что догруживать по частям этот сервер не умеет.
    func roleChatMessagesPage(
        id: String,
        projection: ChatMessageProjection = .list,
        after: Int? = nil,
        before: Int? = nil,
        limit: Int? = nil
    ) async throws -> RoleChatMessagesPage {
        var query: [URLQueryItem] = []
        if projection == .list { query.append(URLQueryItem(name: "projection", value: "list")) }
        if let after { query.append(URLQueryItem(name: "after", value: String(after))) }
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        let (data, _) = try await requestRaw(
            .get, "/chats/\(id)/messages",
            query: query,
            timeout: Self.localSyncTimeout
        )
        return RoleChatMessagesPage(data: data, hasMore: Self.boolean(in: data, key: "has_more"))
    }

    /// Ответ списка задач вместе с отпечатком и курсором дельты.
    public struct TaskListRawResult {
        /// Сырое тело ответа. При 304 — пустое.
        public let data: Data
        /// Сервер ответил «не менялось» (304) — тело не присылали.
        public let notModified: Bool
        /// Отпечаток тела: присылаем обратно — сервер ответит 304, пока
        /// список не менялся.
        public let etag: String?
        /// Курсор дельты (`X-TaskFlow-Sync-Cursor`): по нему потом
        /// спрашиваем «что изменилось», вместо полной перечитки.
        public let cursor: String?
    }

    /// `GET /api/tasks` — сырое тело плюс отпечаток и курсор.
    ///
    /// Отдельный метод, а не `taskList()`: тот декодирует модель и теряет
    /// тело, а в базу нужно класть ответ сервера как есть.
    func taskListRaw(
        includeChildren: Bool = false,
        archived: Bool = false,
        etag: String? = nil,
        projection: TaskListProjection = .list
    ) async throws -> TaskListRawResult {
        var query: [URLQueryItem] = []
        if includeChildren { query.append(URLQueryItem(name: "include_children", value: "true")) }
        if archived { query.append(URLQueryItem(name: "archived", value: "true")) }
        if projection == .list { query.append(URLQueryItem(name: "projection", value: "list")) }
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = etag }
        let (data, http) = try await requestRaw(
            .get, "/tasks",
            query: query,
            timeout: Self.localSyncTimeout,
            acceptedErrorStatuses: [304],
            headers: headers
        )
        let cursor = http.value(forHTTPHeaderField: "X-TaskFlow-Sync-Cursor")
        let newEtag = http.value(forHTTPHeaderField: "ETag")
        if http.statusCode == 304 {
            // При 304 курсор берём только из заголовка: ETag — это отпечаток
            // тела, а не метка времени, и подставлять его в курсор нельзя
            // (сервер поймёт его как мусор и попросит полную перечитку).
            return TaskListRawResult(data: Data(), notModified: true, etag: newEtag ?? etag, cursor: cursor)
        }
        return TaskListRawResult(data: data, notModified: false, etag: newEtag, cursor: cursor)
    }

    /// `GET /api/notifications` — сырое тело (в базу кладём как есть).
    /// Сервер отдаёт ленту простым массивом, без конверта.
    func rawNotifications(unreadOnly: Bool = false) async throws -> Data {
        var query: [URLQueryItem] = []
        if unreadOnly { query.append(URLQueryItem(name: "unread", value: "true")) }
        let (data, _) = try await requestRaw(
            .get, "/notifications",
            query: query,
            timeout: Self.localSyncTimeout
        )
        return data
    }

    /// Разбор JSON-конверта без декодирования модели: нужен только
    /// факт «поле есть». Значения `Bool` и `NSNumber` неразличимы при
    /// разборе `JSONSerialization`, поэтому `false` от `0` не отличить —
    /// для этого признака разницы нет.
    private static func boolean(in data: Data, key: String) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any]
        else { return nil }
        guard let value = object[key] else { return nil }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}
