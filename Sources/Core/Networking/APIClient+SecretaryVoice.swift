import Foundation

/// Ответ `POST /api/secretary/voice-token` (Задача 1 плана Супер Секретарь) —
/// параметры комнаты LiveKit для голосового разговора с Секретарём.
public struct SecretaryVoiceToken: Decodable, Sendable {
    public let url: String
    public let token: String
    public let room: String
}

public extension APIClient {
    /// POST без тела запроса, JSON-ответ — тот же приём, что
    /// `sendRoleChatMessage`/`newRoleChatSession` в `APIClient+RoleChats.swift`
    /// (`request(.post, path)` без `body:`; префикс `/api` добавляет
    /// `buildRequest()` внутри `APIClient` сам).
    func secretaryVoiceToken() async throws -> SecretaryVoiceToken {
        try await request(.post, "/secretary/voice-token")
    }
}
