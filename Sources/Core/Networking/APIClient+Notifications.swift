import Foundation

/// Уведомления — spec/API.md §5.7.
public extension APIClient {
    /// `unreadOnly` — только непрочитанные (`?unread=true`). Параметр на
    /// сервере необязательный: без него ответ прежний (вся лента), поэтому
    /// старые сборки клиента работают как раньше.
    func notifications(unreadOnly: Bool = false) async throws -> [ApiNotification] {
        var query: [URLQueryItem] = []
        if unreadOnly { query.append(URLQueryItem(name: "unread", value: "true")) }
        return try await request(.get, "/notifications", query: query)
    }

    /// Сервер принимает только `PATCH /notifications/:id/read` без тела и
    /// отвечает подтверждением операции. Снимок уведомлений надо брать
    /// отдельным GET, а не декодировать этот ответ как `ApiNotification`.
    func markNotificationRead(id: String) async throws {
        let _: APIOkResponse = try await request(.patch, "/notifications/\(id)/read")
    }

    func deleteNotification(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/notifications/\(id)")
    }
}
