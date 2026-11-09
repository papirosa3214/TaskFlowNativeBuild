import Foundation

/// Расход OpenCode — раздел экрана «Статистика» (владелец 09.11.2026).
///
/// Ответ сервера `GET /api/opencode/usage?window=today|week|month`.
/// Данные — из локальной базы OpenCode на .110 (`~/.local/share/opencode`),
/// поэтому это **не** расход ролей TaskFlow и не баланс аккаунта: только то,
/// что OpenCode сам записал о своих вызовах.
struct OpenCodeUsage: Decodable, Sendable {
    struct Model: Decodable, Sendable, Identifiable {
        let model: String
        let provider: String
        let calls: Int
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let costUsd: Double

        var id: String { provider + "/" + model }
        var totalTokens: Int { inputTokens + outputTokens }
    }

    let available: Bool
    let database: String
    let window: String
    let since: String?
    let calls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let costUsd: Double
    /// Вызовы без данных о токенах: цифры выше — только по известным.
    let unknownUsageCalls: Int
    let models: [Model]
    /// Пояснение источника — показывается под цифрами как есть.
    let note: String

    /// Стоимость словами. Ноль — честное «$0», а не пустота: у бесплатных
    /// моделей OpenCode `cost: 0` в базе.
    var costText: String {
        String(format: "$%.2f", costUsd).replacingOccurrences(of: ".", with: ",")
    }
}
