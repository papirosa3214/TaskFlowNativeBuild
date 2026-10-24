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
    /// Устойчивый порядок моделей: сначала самые дорогие по токенам за период.
    /// Считается ОДИН РАЗ при разборе ответа: раньше это свойство пересобирало
    /// словарь и сортировало его на каждый вызов `shadeIndex` — то есть на каждую
    /// модель в легенде и в столбиках.
    let modelOrder: [String]

    init(trackingSince: String?, totals: AIUsageTotals, models: [AIUsageModel],
         daily: [AIUsageDay], dailyByModel: [AIUsageDayModel]) {
        self.trackingSince = trackingSince
        self.totals = totals
        self.models = models
        self.daily = daily
        self.dailyByModel = dailyByModel
        self.modelOrder = Self.order(for: dailyByModel)
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
        modelOrder = Self.order(for: dailyByModel)
    }

    private static func order(for rows: [AIUsageDayModel]) -> [String] {
        var totals: [String: Int] = [:]
        for row in rows { totals[row.model, default: 0] += row.totalTokens }
        return totals.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map(\.key)
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

/// Короткая запись количества токенов для экрана статистики: миллиарды и
/// миллионы не должны растягиваться в «4720,7 млн» (просьба владельца
/// 24.10.2026 — «чтобы числа были коротенькими»).
enum AIUsageFormat {
    static func tokens(_ value: Int) -> String {
        func number(_ raw: Double, decimals: Int) -> String {
            let text = String(format: "%.\(decimals)f", raw).replacingOccurrences(of: ".", with: ",")
            // «500,0 млн» читается хуже, чем «500 млн»: хвост из нулей не нужен.
            return text.hasSuffix(",0") ? String(text.dropLast(2)) : text
        }
        switch value {
        case 1_000_000_000...:
            return number(Double(value) / 1_000_000_000, decimals: 1) + " млрд"
        case 1_000_000...:
            return number(Double(value) / 1_000_000, decimals: 1) + " млн"
        case 10_000...:
            return number(Double(value) / 1_000, decimals: 0) + " тыс"
        default:
            return String(value)
        }
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
