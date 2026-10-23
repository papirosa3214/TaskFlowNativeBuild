import Foundation

struct AIUsage: Decodable, Sendable {
    let trackingSince: String?
    let totals: AIUsageTotals
    let models: [AIUsageModel]
    let daily: [AIUsageDay]
}
struct AIUsageTotals: Decodable, Sendable {
    let calls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let totalTokens: Int
    let estimatedCostUsd: Double?
    let unpricedCalls: Int
    let cacheHitRate: Double?
    var costLabel: String {
        guard let cost = estimatedCostUsd else { return "Нет данных" }
        let money = cost < 0.01 ? "< $0,01" : "$" + String(format: "%.2f", cost).replacingOccurrences(of: ".", with: ",")
        return (unpricedCalls > 0 ? "Частично ≈ " : "≈ ") + money
    }
}
struct AIUsageModel: Decodable, Identifiable, Sendable {
    var id: String { provider + ":" + model }
    let provider: String
    let model: String
    let calls: Int
    let totalTokens: Int
    let estimatedCostUsd: Double?
    let unpricedCalls: Int
}
struct AIUsageDay: Decodable, Identifiable, Sendable {
    var id: String { day }
    let day: String
    let calls: Int
    let totalTokens: Int
    let estimatedCostUsd: Double?
}
