import Foundation

public struct RoleComposio: Decodable, Sendable {
    public let enabled: Bool
    /// nil means the whole catalog; an empty array grants no toolkits.
    public let toolkits: [String]?
    public let configured: Bool
    public let available: Bool
    public let catalog: [ComposioToolkit]
    public let error: String?
}

public struct ComposioToolkit: Decodable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let connected: Bool
    public let noAuth: Bool
    public var id: String { slug }
}

public struct ComposioAuthorization: Decodable, Sendable {
    public let url: String
}
