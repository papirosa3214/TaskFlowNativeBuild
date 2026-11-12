import Foundation

public enum SessionPromptMode: String, Codable, Sendable {
    case prompt
    case steer
    case followUp = "follow_up"
}

public struct PromptSessionRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let text: String
    public let mode: SessionPromptMode

    public init(requestId: String, text: String, mode: SessionPromptMode) {
        self.requestId = requestId
        self.text = text
        self.mode = mode
    }
}

public struct SessionEntryCommandRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let entryId: String

    public init(requestId: String, entryId: String) {
        self.requestId = requestId
        self.entryId = entryId
    }
}

/// `PUT /api/sessions/:id/model` — модель выбирается для сессии целиком,
/// а не для одного сообщения: Pi пишет model_change в транскрипт.
public struct SetSessionModelRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let provider: String
    public let model: String

    public init(requestId: String, provider: String, model: String) {
        self.requestId = requestId
        self.provider = provider
        self.model = model
    }
}

public struct AbortSessionRequest: Codable, Equatable, Sendable {
    public let requestId: String

    public init(requestId: String) { self.requestId = requestId }
}

public struct CommandAcknowledgement: Equatable, Sendable, JSONValueDecodable {
    public let requestId: String
    public let accepted: Bool?
    public let aborted: Bool?

    public init(requestId: String, accepted: Bool? = nil, aborted: Bool? = nil) {
        self.requestId = requestId
        self.accepted = accepted
        self.aborted = aborted
    }

    public init?(json: JSONValue) {
        guard let requestId = json["requestId"]?.stringValue else { return nil }
        self.init(
            requestId: requestId,
            accepted: json["accepted"]?.boolValue,
            aborted: json["aborted"]?.boolValue
        )
    }
}
