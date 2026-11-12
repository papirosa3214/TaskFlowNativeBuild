import Foundation

/// Модель, которую можно собрать из разобранного JSON. Разбор идёт своим
/// парсером (см. \`JSONValue.parse\`), а не \`JSONDecoder\`: дерево сессии Pi
/// слишком глубокое для Codable и для лимита \`JSONSerialization\` в 512
/// вложенных контейнеров.
public protocol JSONValueDecodable {
    init?(json: JSONValue)
}

public enum SessionRelation: String, Sendable {
    case root
    case fork
    case subagent
}

public struct SessionSummary: Equatable, Sendable, Identifiable, JSONValueDecodable {
    public let id: String
    public let cwd: String
    public let name: String?
    public let parentSession: String?
    public let relation: SessionRelation?
    /// Метки владельца и превью строки (сервер, 12.11.2026).
    public var title: String?
    public var firstMessage: String?
    public var modified: String?
    public var projectID: String?
    public var pinned: Bool
    public var archivedAt: String?

    public init(
        id: String,
        cwd: String,
        name: String? = nil,
        parentSession: String? = nil,
        relation: SessionRelation? = nil,
        title: String? = nil,
        firstMessage: String? = nil,
        modified: String? = nil,
        projectID: String? = nil,
        pinned: Bool = false,
        archivedAt: String? = nil
    ) {
        self.id = id
        self.cwd = cwd
        self.name = name
        self.parentSession = parentSession
        self.relation = relation
        self.title = title
        self.firstMessage = firstMessage
        self.modified = modified
        self.projectID = projectID
        self.pinned = pinned
        self.archivedAt = archivedAt
    }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.stringValue, let cwd = json["cwd"]?.stringValue else { return nil }
        let pinned: Bool = if case .bool(let value)? = json["pinned"] { value } else { false }
        self.init(
            id: id,
            cwd: cwd,
            name: json["name"]?.stringValue,
            parentSession: json["parentSession"]?.stringValue,
            relation: json["relation"]?.stringValue.flatMap(SessionRelation.init(rawValue:)),
            title: json["title"]?.stringValue,
            firstMessage: json["firstMessage"]?.stringValue,
            modified: json["modified"]?.stringValue,
            projectID: json["projectId"]?.stringValue,
            pinned: pinned,
            archivedAt: json["archivedAt"]?.stringValue
        )
    }
}

public struct SessionListResponse: Equatable, Sendable, JSONValueDecodable {
    public let sessions: [SessionSummary]

    public init(sessions: [SessionSummary]) { self.sessions = sessions }

    public init?(json: JSONValue) {
        guard let items = json["sessions"]?.arrayValue else { return nil }
        sessions = items.compactMap(SessionSummary.init(json:))
    }
}

/// Модель, на которой идёт сессия. Владелец выбора — сервер: клиент только
/// показывает то, что вернул Pi, и просит переключить.
public struct SessionModelRef: Equatable, Sendable, JSONValueDecodable {
    public let provider: String
    public let id: String

    public init(provider: String, id: String) {
        self.provider = provider
        self.id = id
    }

    public init?(json: JSONValue) {
        guard let provider = json["provider"]?.stringValue, let id = json["id"]?.stringValue else {
            return nil
        }
        self.init(provider: provider, id: id)
    }
}

public struct SessionSnapshot: Equatable, Sendable, Identifiable, JSONValueDecodable {
    public let id: String
    public let cwd: String
    public let sessionFile: String?
    public let parentSession: String?
    public let relation: SessionRelation?
    public let name: String?
    public let model: SessionModelRef?
    public let leafId: String?
    public var isStreaming: Bool
    public var isIdle: Bool
    public let entries: [JSONValue]
    public let tree: [JSONValue]

    public init(
        id: String,
        cwd: String,
        sessionFile: String? = nil,
        parentSession: String? = nil,
        relation: SessionRelation? = nil,
        name: String? = nil,
        model: SessionModelRef? = nil,
        leafId: String? = nil,
        isStreaming: Bool,
        isIdle: Bool,
        entries: [JSONValue],
        tree: [JSONValue]
    ) {
        self.id = id
        self.cwd = cwd
        self.sessionFile = sessionFile
        self.parentSession = parentSession
        self.relation = relation
        self.name = name
        self.model = model
        self.leafId = leafId
        self.isStreaming = isStreaming
        self.isIdle = isIdle
        self.entries = entries
        self.tree = tree
    }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.stringValue, let cwd = json["cwd"]?.stringValue else { return nil }
        self.init(
            id: id,
            cwd: cwd,
            sessionFile: json["sessionFile"]?.stringValue,
            parentSession: json["parentSession"]?.stringValue,
            relation: json["relation"]?.stringValue.flatMap(SessionRelation.init(rawValue:)),
            name: json["name"]?.stringValue,
            model: json["model"].flatMap(SessionModelRef.init(json:)),
            leafId: json["leafId"]?.stringValue,
            isStreaming: json["isStreaming"]?.boolValue ?? false,
            isIdle: json["isIdle"]?.boolValue ?? false,
            entries: json["entries"]?.arrayValue ?? [],
            tree: json["tree"]?.arrayValue ?? []
        )
    }
}

public struct SessionResponse: Equatable, Sendable, JSONValueDecodable {
    public let session: SessionSnapshot

    public init(session: SessionSnapshot) { self.session = session }

    public init?(json: JSONValue) {
        guard let session = json["session"].flatMap(SessionSnapshot.init(json:)) else { return nil }
        self.init(session: session)
    }
}

public struct SessionEventEnvelope: Equatable, Sendable, JSONValueDecodable {
    public let cursor: String
    public let sessionId: String
    public let entryId: String?
    public let type: String
    public let timestamp: String
    public let payload: [String: JSONValue]

    public init(
        cursor: String,
        sessionId: String,
        entryId: String? = nil,
        type: String,
        timestamp: String,
        payload: [String: JSONValue]
    ) {
        self.cursor = cursor
        self.sessionId = sessionId
        self.entryId = entryId
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }

    public init?(json: JSONValue) {
        guard let cursor = json["cursor"]?.stringValue,
              let sessionId = json["sessionId"]?.stringValue,
              let type = json["type"]?.stringValue,
              let timestamp = json["timestamp"]?.stringValue else { return nil }
        self.init(
            cursor: cursor,
            sessionId: sessionId,
            entryId: json["entryId"]?.stringValue,
            type: type,
            timestamp: timestamp,
            payload: json["payload"]?.objectValue ?? [:]
        )
    }
}

public struct SessionReconnectPayload: Equatable, Sendable, JSONValueDecodable {
    public let resetRequired: Bool
    public let events: [SessionEventEnvelope]
    public let snapshot: SessionSnapshot?

    public init(resetRequired: Bool, events: [SessionEventEnvelope], snapshot: SessionSnapshot?) {
        self.resetRequired = resetRequired
        self.events = events
        self.snapshot = snapshot
    }

    public init?(json: JSONValue) {
        self.init(
            resetRequired: json["resetRequired"]?.boolValue ?? false,
            events: (json["events"]?.arrayValue ?? []).compactMap(SessionEventEnvelope.init(json:)),
            snapshot: json["snapshot"].flatMap(SessionSnapshot.init(json:))
        )
    }
}

public struct SessionRenderedMessage: Equatable, Sendable {
    public let role: String
    public let text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public enum ChildSessionActivity: Equatable, Sendable {
    case running
    case settled
    case aborted
    case attention
}

public enum CommandDelivery: Equatable, Sendable {
    case idle
    case sending(requestId: String)
    case acknowledged(requestId: String)
    case unknown(requestId: String)
    case failed(requestId: String, message: String)
}

public struct SessionState: Equatable, Sendable {
    public var snapshot: SessionSnapshot?
    public var messages: [SessionRenderedMessage]
    public var transientAssistantText: String
    public var lastCursor: String?
    public var seenCursors: Set<String>
    public var unknownEvents: [SessionEventEnvelope]
    public var childActivity: [String: ChildSessionActivity]
    public var needsSnapshotReset: Bool
    public var commandDelivery: CommandDelivery

    public init(snapshot: SessionSnapshot?) {
        self.snapshot = snapshot
        self.messages = []
        self.transientAssistantText = ""
        self.lastCursor = nil
        self.seenCursors = []
        self.unknownEvents = []
        self.childActivity = [:]
        self.needsSnapshotReset = false
        self.commandDelivery = .idle
    }

    public mutating func markCommandStarted(requestId: String) {
        commandDelivery = .sending(requestId: requestId)
    }

    public mutating func markCommandAcknowledged(requestId: String) {
        commandDelivery = .acknowledged(requestId: requestId)
    }

    public mutating func markCommandTimedOut(requestId: String) {
        commandDelivery = .unknown(requestId: requestId)
    }

    public mutating func markCommandFailed(requestId: String, message: String) {
        commandDelivery = .failed(requestId: requestId, message: message)
    }
}
