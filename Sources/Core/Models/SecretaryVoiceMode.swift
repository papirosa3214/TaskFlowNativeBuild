import Foundation

/// Opt-in transport for the next voice call. The existing stack remains the default.
public enum SecretaryVoiceMode: String, CaseIterable, Identifiable, Sendable {
    case standard = "current"
    case pipecatLive = "pipecat-live"
    case pipecatChat = "pipecat-chat"

    public static let storageKey = "secretary.voice.mode"
    public var id: String { rawValue }
    public static func fromStoredValue(_ value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .standard
    }
    public static var selected: Self {
        fromStoredValue(UserDefaults.standard.string(forKey: storageKey))
    }
    public var supportsScreen: Bool { self != .pipecatChat }
    public var title: String {
        switch self {
        case .standard: "Текущий · LiveKit + Gemini"
        case .pipecatLive: "Проверка · Pipecat + Gemini Live"
        case .pipecatChat: "Проверка · Pipecat + исполнитель чата"
        }
    }
    public var explanation: String {
        switch self {
        case .standard: "Обычный голосовой разговор."
        case .pipecatLive: "Эксперимент с Gemini Live и общими инструментами TaskFlow."
        case .pipecatChat: "Распознавание завершённой фразы, выполнение в исходном чате и озвучка ответа. Показ экрана недоступен."
        }
    }
    public func requestFields(voice: String, chatID: String) -> [String: String] {
        var fields = ["voice": voice, "chat_id": chatID]
        if self != .standard { fields["mode"] = rawValue }
        return fields
    }
}
