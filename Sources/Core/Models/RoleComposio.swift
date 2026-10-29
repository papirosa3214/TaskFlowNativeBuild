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

/// Подключённый аккаунт сервиса (у одного сервиса бывает несколько адресов).
public struct ComposioAccount: Decodable, Sendable, Identifiable {
    public let id: String
    /// Адрес аккаунта (почта); nil — сервис адрес не отдаёт.
    public let address: String?
    /// Подпись, которую владелец дал аккаунту.
    public let alias: String?
    /// Состояние подключения у Composio (`ACTIVE` и другие).
    public let status: String
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, address, alias, status
        case createdAt = "created_at"
    }
}

/// Ответ сервера со списком аккаунтов сервиса.
public struct ComposioAccountList: Decodable, Sendable {
    public let items: [ComposioAccount]
}

/// Состояние тумблеров подключения к сервисам Composio.
///
/// Пока идёт авторизация, тумблер должен показывать то, на что владелец
/// нажал, а не серверное состояние: иначе переключатель отпрыгивает назад
/// и кажется, что ничего не произошло. Как только сервер подтвердил
/// состояние (каталог вернул «подключено»), ожидание заканчивается.
public struct ComposioToggleState: Sendable {
    /// Сервисы, у которых тумблер меняется: ключ сервиса → новое состояние.
    public private(set) var pending: [String: Bool] = [:]

    public init() {}

    /// Владелец нажал тумблер: запоминаем новое состояние.
    public mutating func begin(_ slug: String, isOn: Bool) {
        pending[slug] = isOn
    }

    /// Запрос не удался (или состояние сняли) — возвращаем серверное.
    public mutating func cancel(_ slug: String) {
        pending[slug] = nil
    }

    /// Что показывать на тумблере.
    public func isOn(_ slug: String, connected: Bool) -> Bool {
        pending[slug] ?? connected
    }

    /// Сервер ответил: ожидание снимается там, где состояние совпало.
    public mutating func reconcile(connected: [String: Bool]) {
        for (slug, value) in pending {
            guard let serverValue = connected[slug] else { continue }
            if serverValue == value { pending[slug] = nil }
        }
    }
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

/// Сервисы общего аккаунта TaskFlow, включая разрешённые роли сервисы вне страницы каталога.
public struct ComposioConnectionOverview: Decodable, Sendable {
    public let catalog: [ComposioToolkit]
    public let services: [RoleIntegrationToolkit]
    public let configured: Bool?
    public let available: Bool?
    public let roles: [ComposioWorkspacePolicy]?
    public let catalogCursor: String?
    public let catalogTotalPages: Int?
    public let error: String?

    public var connectedServices: [RoleIntegrationToolkit] {
        var bySlug = Dictionary(catalog.map { item in
            (item.slug, RoleIntegrationToolkit(slug: item.slug, name: item.name, logo: item.logo, description: item.description, connected: item.connected))
        }, uniquingKeysWith: { _, latest in latest })
        for service in services { bySlug[service.slug] = service }
        return bySlug.values.filter { $0.connected == true }.sorted {
            ($0.name ?? $0.slug).localizedCaseInsensitiveCompare($1.name ?? $1.slug) == .orderedAscending
        }
    }
}

public struct ComposioWorkspacePolicy: Decodable, Sendable {
    public let role: String
    public let enabled: Bool
    public let toolkits: [String]?
}
