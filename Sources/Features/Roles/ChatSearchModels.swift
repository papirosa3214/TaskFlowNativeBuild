import Foundation

/// Строка выдачи: что нашли и в каком месте переписки.
public struct ChatSearchHit: Identifiable, Decodable, Sendable {
    public let chatID: String
    public let title: String
    public let subject: String?
    public let hitText: String?

    public var id: String { chatID }

    public enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case title
        case subject
        case hitText = "hit_text"
    }

    public var subtitle: String {
        if let hit = hitText, !hit.isEmpty { return hit }
        if let subject, !subject.isEmpty { return subject }
        return "Чат"
    }
}

public struct ChatSearchEnvelope: Decodable, Sendable {
    public let results: [ChatSearchHit]
}
