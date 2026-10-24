import Foundation

struct AIUsage: Decodable, Sendable {
    let trackingSince: String?
    let totals: AIUsageTotals
    let models: [AIUsageModel]
    let daily: [AIUsageDay]
    /// Расход в разрезе «день × модель» — для столбиков и выбора дня.
    /// Сервер отдаёт его отдельным полем `dailyByModel`; старый ответ без
    /// поля декодируется пустым списком, и экран остаётся с общими столбиками.
    let dailyByModel: [AIUsageDayModel]

    init(trackingSince: String?, totals: AIUsageTotals, models: [AIUsageModel],
         daily: [AIUsageDay], dailyByModel: [AIUsageDayModel]) {
        self.trackingSince = trackingSince
        self.totals = totals
        self.models = models
        self.daily = daily
        self.dailyByModel = dailyByModel
    }

    private enum CodingKeys: String, CodingKey {
        case trackingSince, totals, models, daily, dailyByModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackingSince = try c.decodeIfPresent(String.self, forKey: .trackingSince)
        totals = try c.decode(AIUsageTotals.self, forKey: .totals)
        models = try c.decodeIfPresent([AIUsageModel].self, forKey: .models) ?? []
        daily = try c.decodeIfPresent([AIUsageDay].self, forKey: .daily) ?? []
        dailyByModel = try c.decodeIfPresent([AIUsageDayModel].self, forKey: .dailyByModel) ?? []
    }

    /// Есть ли на сервере разрез по моделям внутри дня.
    var hasModelBreakdown: Bool { !dailyByModel.isEmpty }

    /// Итоги выбранного дня; `nil` — весь период. Неизвестный день — снова
    /// общие итоги, чтобы выбранным не оказался день, которого нет в ответе.
    func totals(for day: String?) -> AIUsageTotals {
        guard let day, let picked = daily.first(where: { $0.day == day }) else { return totals }
        return picked.totals
    }

    /// Модели выбранного дня, по убыванию токенов. У всего периода — общий
    /// разрез сервера (`models`), у неизвестного дня — пусто.
    func models(for day: String?) -> [AIUsageModel] {
        guard let day else { return models }
        guard hasModelBreakdown else { return [] }
        return dailyByModel
            .filter { $0.day == day }
            .sorted { $0.totalTokens > $1.totalTokens }
            .map { AIUsageModel(provider: $0.provider, model: $0.model, calls: $0.calls,
                                totalTokens: $0.totalTokens, estimatedCostUsd: $0.estimatedCostUsd,
                                unpricedCalls: $0.unpricedCalls) }
    }

    /// Пары «день · модель» для столбиков, по убыванию общего расхода за
    /// период — порядок задаёт и очередь оттенков в легенде.
    var chartSegments: [AIUsageDayModel] {
        AIUsageDayModel.sortedForChart(dailyByModel, order: modelOrder)
    }

    /// Устойчивый порядок моделей: сначала самые дорогие по токенам за период.
    var modelOrder: [String] {
        var totals: [String: Int] = [:]
        for row in dailyByModel { totals[row.model, default: 0] += row.totalTokens }
        return totals.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map(\.key)
    }

    /// Оттенок модели в столбиках: чем больше расход, тем насыщеннее.
    func shadeIndex(for model: String) -> Int {
        modelOrder.firstIndex(of: model) ?? modelOrder.count
    }
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
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let totalTokens: Int
    let estimatedCostUsd: Double?
    let unpricedCalls: Int
    let cacheHitRate: Double?

    /// Итоги дня в той же форме, что общие: цифры под графиком не меняют вид
    /// при выборе дня.
    var totals: AIUsageTotals {
        AIUsageTotals(calls: calls, inputTokens: inputTokens, outputTokens: outputTokens,
                      cacheReadTokens: cacheReadTokens, cacheWriteTokens: cacheWriteTokens,
                      totalTokens: totalTokens, estimatedCostUsd: estimatedCostUsd,
                      unpricedCalls: unpricedCalls, cacheHitRate: cacheHitRate)
    }
}

/// Одна строка разреза «день × модель».
struct AIUsageDayModel: Decodable, Identifiable, Sendable {
    var id: String { day + ":" + provider + ":" + model }
    let day: String
    let provider: String
    let model: String
    let calls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let totalTokens: Int
    let estimatedCostUsd: Double?
    let unpricedCalls: Int
    let cacheHitRate: Double?

    /// Для `Chart`: один день идёт одной группой, а внутри — модели в порядке
    /// оттенков, иначе Swift Charts переставляет сегменты сам.
    static func sortedForChart(_ rows: [AIUsageDayModel], order: [String]) -> [AIUsageDayModel] {
        func rank(_ model: String) -> Int { order.firstIndex(of: model) ?? order.count }
        return rows.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            return rank(lhs.model) < rank(rhs.model)
        }
    }
}
