import Foundation

public struct RoleComposio: Decodable, Sendable {
    public let enabled: Bool
    /// nil means the whole catalog; an empty array grants no toolkits.
    public let toolkits: [String]?
    public let configured: Bool
    public let available: Bool
    public let catalog: [ComposioToolkit]
    /// Курсор следующей страницы каталога (nil — страниц больше нет).
    public let catalogCursor: String?
    /// Сколько страниц в каталоге всего (nil — неизвестно).
    public let catalogTotalPages: Int?
    public let error: String?
}

public struct ComposioToolkit: Decodable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    /// Логотип сервиса от Composio.
    public let logo: URL?
    /// Описание сервиса по-русски; nil — перевода нет.
    public let description: String?
    public let connected: Bool
    public let noAuth: Bool
    public var id: String { slug }
}

/// Блок `integrations` профиля роли (`GET /api/roles/:role`): сервисы
/// Composio, которые роли разрешены, и подключены ли они у владельца.
public struct RoleIntegrations: Decodable, Sendable {
    public let enabled: Bool
    public let toolkits: [RoleIntegrationToolkit]
    public let connectedKnown: Bool
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case enabled, toolkits, error
        case connectedKnown = "connected_known"
    }
}

public struct RoleIntegrationToolkit: Decodable, Identifiable, Sendable {
    public let slug: String
    /// Название от Composio; nil — каталог не ответил.
    public let name: String?
    public let logo: URL?
    public let description: String?
    /// nil — состояние подключения неизвестно.
    public let connected: Bool?
    public var id: String { slug }
}

public struct ComposioAuthorization: Decodable, Sendable {
    public let url: String
}

/// Changes one service without replacing unrelated role permissions.
struct ComposioAccessPolicy: Equatable, Sendable {
    var enabled: Bool
    var toolkits: [String]?

    func allows(_ toolkit: String?) -> Bool {
        guard enabled else { return false }
        guard let toolkit else { return toolkits == nil }
        return toolkits == nil || toolkits!.contains(toolkit)
    }

    func changing(_ toolkit: String?, allowed: Bool) throws -> Self {
        guard let toolkit else {
            return allowed ? Self(enabled: true, toolkits: nil) : Self(enabled: false, toolkits: toolkits)
        }
        // An unrestricted catalog cannot express a single-service exclusion.
        // Keep that existing permission explicit rather than revoking other services.
        if enabled && toolkits == nil {
            if !allowed { throw ComposioAccessError.wholeCatalog }
            return self
        }
        var services = Set(enabled ? (toolkits ?? []) : [])
        if allowed { services.insert(toolkit) } else { services.remove(toolkit) }
        return Self(enabled: allowed || (enabled && !services.isEmpty), toolkits: services.sorted())
    }
}

enum ComposioAccessError: LocalizedError {
    case wholeCatalog
    var errorDescription: String? {
        "У роли открыт весь каталог. Сначала измените доступ в разделе «Весь каталог»."
    }
}
