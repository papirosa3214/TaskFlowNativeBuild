import Foundation

public extension APIClient {
    func composioConnections() async throws -> ComposioConnectionOverview {
        try await request(.get, "/integrations/composio")
    }

    func roleComposio(role: String, search: String = "", cursor: String? = nil, limit: Int? = nil) async throws -> RoleComposio {
        var query = [URLQueryItem(name: "search", value: search)]
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await request(.get, "/roles/\(role)/composio", query: query)
    }

    func saveRoleComposio(role: String, enabled: Bool, toolkits: [String]?) async throws {
        let body: [String: JSONValue] = [
            "enabled": .bool(enabled),
            "toolkits": toolkits.map { JSONValue.array($0.map(JSONValue.string)) } ?? .null
        ]
        try await requestVoid(.patch, "/roles/\(role)/composio", body: body)
    }

    func authorizeRoleComposio(role: String, toolkit: String) async throws -> ComposioAuthorization {
        let body: [String: JSONValue] = ["toolkit": .string(toolkit)]
        return try await request(.post, "/roles/\(role)/composio/authorize", body: body)
    }

    /// Аккаунты сервиса у владельца (у одного сервиса бывает несколько адресов).
    func composioAccounts(toolkit: String) async throws -> [ComposioAccount] {
        let list: ComposioAccountList = try await request(.get, "/integrations/composio/\(toolkit)/accounts")
        return list.items
    }

    /// Ссылка на подключение нового аккаунта сервиса: по ней владелец проходит
    /// авторизацию в браузере Composio.
    func composioLinkAccount(toolkit: String) async throws -> ComposioAuthorization {
        try await request(.post, "/integrations/composio/\(toolkit)/accounts", body: [String: JSONValue]())
    }

    /// Отключить аккаунт сервиса.
    func composioDeleteAccount(toolkit: String, id: String) async throws {
        try await requestVoid(.delete, "/integrations/composio/\(toolkit)/accounts/\(id)")
    }
}
