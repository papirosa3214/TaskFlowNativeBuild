import Foundation

public extension APIClient {
    /// Каталог постраничный: курсор первой страницы — nil, дальше — из ответа.
    func roleComposio(role: String, search: String = "", cursor: String? = nil) async throws -> RoleComposio {
        var query = [URLQueryItem(name: "search", value: search)]
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
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
}
