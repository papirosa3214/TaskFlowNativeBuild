import Foundation

/// How work is delivered. Independent of planning, goal and research settings.
public enum ChatExecutionMode: String, Codable, CaseIterable, Sendable {
    case chat, card

    public var title: String { self == .chat ? "В чате" : "По карточке" }

    public static func resolve(stored: Self?, taskID: String?, parentChatID: String?) -> Self {
        stored ?? (taskID != nil && parentChatID != nil ? .card : .chat)
    }
}
