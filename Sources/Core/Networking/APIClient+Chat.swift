import Foundation

/// Внутренний чат координации агентов — spec/API.md §5.8. Минимальный набор
/// методов для экрана «Чат» (Волна 2). Удалены 2026-09-11 по DEAD-CODE-CLEANUP-REPORT.md:
/// chatMessages, sendChatMessage, sendChatTyping, markChatRead — старые контракты,
/// заменены `ChatAPI.swift` в `Sources/Features/Chat/`.
public extension APIClient {

    func chatParticipants(channel: ChatChannel? = nil) async throws -> [ApiChatParticipant] {
        var query: [URLQueryItem] = []
        if let channel { query.append(URLQueryItem(name: "channel", value: channel.rawValue)) }
        return try await request(.get, "/chat/participants", query: query)
    }

    func chatStats() async throws -> ApiChatStats {
        try await request(.get, "/chat/stats")
    }
}
