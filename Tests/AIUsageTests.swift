import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class AIUsageTests: XCTestCase {
    private func totals(cost: Double?, unpriced: Int) -> AIUsageTotals {
        AIUsageTotals(calls: 2, inputTokens: 100, outputTokens: 20, cacheReadTokens: 900,
                      cacheWriteTokens: 0, totalTokens: 1020, estimatedCostUsd: cost,
                      unpricedCalls: unpriced, cacheHitRate: 0.9)
    }
    func testMissingCostIsNotZeroDollars() {
        XCTAssertEqual(totals(cost: nil, unpriced: 2).costLabel, "Нет данных")
    }
    func testPartialCostIsExplicitlyPartial() {
        XCTAssertTrue(totals(cost: 0.12, unpriced: 1).costLabel.contains("Частично"))
        XCTAssertTrue(totals(cost: 0.12, unpriced: 0).costLabel.contains("0,12"))
    }
    func testDecodeServerContractWithUnknownCost() throws {
        let json = #"{"trackingSince":null,"totals":{"calls":0,"inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"totalTokens":0,"estimatedCostUsd":null,"unpricedCalls":0,"cacheHitRate":null},"models":[],"daily":[]}"#
        let decoded = try JSONDecoder().decode(AIUsage.self, from: Data(json.utf8))
        XCTAssertNil(decoded.totals.estimatedCostUsd)
        XCTAssertNil(decoded.totals.cacheHitRate)
    }

    // MARK: - Выбор дня на графике

    private func model(_ provider: String, _ name: String, tokens: Int, calls: Int = 1, cost: Double? = 1) -> AIUsageModel {
        AIUsageModel(provider: provider, model: name, calls: calls, totalTokens: tokens,
                     estimatedCostUsd: cost, unpricedCalls: 0)
    }

    private func dayModel(_ day: String, _ name: String, tokens: Int) -> AIUsageDayModel {
        AIUsageDayModel(day: day, provider: "minimax", model: name, calls: 2,
                        inputTokens: tokens / 2, outputTokens: 0, cacheReadTokens: tokens / 2,
                        cacheWriteTokens: 0, totalTokens: tokens, estimatedCostUsd: 2,
                        unpricedCalls: 0, cacheHitRate: 0.5)
    }

    private func day(_ key: String, tokens: Int, cost: Double) -> AIUsageDay {
        AIUsageDay(day: key, calls: 4, inputTokens: tokens / 2, outputTokens: 30,
                   cacheReadTokens: tokens / 2, cacheWriteTokens: 0, totalTokens: tokens,
                   estimatedCostUsd: cost, unpricedCalls: 0, cacheHitRate: 0.5)
    }

    private var twoDaysUsage: AIUsage {
        AIUsage(trackingSince: nil,
                totals: totals(cost: 10, unpriced: 0),
                models: [model("minimax", "M3.1-Flash", tokens: 5_000),
                         model("opencode-go", "deepseek-v4.1-flash", tokens: 1_000)],
                daily: [day("2026-10-23", tokens: 4_000, cost: 8),
                        day("2026-10-24", tokens: 2_000, cost: 2)],
                dailyByModel: [dayModel("2026-10-23", "M3.1-Flash", tokens: 3_500),
                               dayModel("2026-10-23", "deepseek-v4.1-flash", tokens: 500),
                               dayModel("2026-10-24", "M3.1-Flash", tokens: 2_000)])
    }

    func testSelectedDayTotalsReplaceOverall() {
        let usage = twoDaysUsage
        XCTAssertEqual(usage.totals(for: nil).totalTokens, 1_020)
        let picked = usage.totals(for: "2026-10-23")
        XCTAssertEqual(picked.totalTokens, 4_000)
        XCTAssertEqual(picked.estimatedCostUsd, 8)
        XCTAssertEqual(picked.calls, 4)
    }

    func testSelectedDayModelsAreOnlyThatDay() {
        let usage = twoDaysUsage
        let models = usage.models(for: "2026-10-23")
        XCTAssertEqual(models.map(\.model), ["M3.1-Flash", "deepseek-v4.1-flash"])
        XCTAssertEqual(models.first?.totalTokens, 3_500)
        XCTAssertEqual(usage.models(for: nil).map(\.model), ["M3.1-Flash", "deepseek-v4.1-flash"])
    }

    func testUnknownDayFallsBackToOverallTotalsWithoutModels() {
        let usage = twoDaysUsage
        XCTAssertEqual(usage.totals(for: "2026-01-01").totalTokens, 1_020)
        XCTAssertTrue(usage.models(for: "2026-01-01").isEmpty)
    }

    func testOldServerWithoutBreakdownKeepsChartOff() {
        let usage = AIUsage(trackingSince: nil, totals: totals(cost: 1, unpriced: 0),
                            models: [model("minimax", "M3.1-Flash", tokens: 10)],
                            daily: [day("2026-10-23", tokens: 10, cost: 1)],
                            dailyByModel: [])
        XCTAssertFalse(usage.hasModelBreakdown)
        XCTAssertTrue(usage.models(for: nil).map(\.model) == ["M3.1-Flash"])
    }

    func testDayBreakdownDecodesFromServerPayload() throws {
        let json = #"{"trackingSince":null,"totals":{"calls":1,"inputTokens":1,"outputTokens":1,"cacheReadTokens":0,"cacheWriteTokens":0,"totalTokens":2,"estimatedCostUsd":1,"unpricedCalls":0,"cacheHitRate":0},"models":[],"daily":[],"dailyByModel":[{"day":"2026-10-23","provider":"minimax","model":"M3.1-Flash","calls":1,"inputTokens":1,"outputTokens":1,"cacheReadTokens":0,"cacheWriteTokens":0,"totalTokens":2,"estimatedCostUsd":1,"unpricedCalls":0,"cacheHitRate":0}]}"#
        let decoded = try JSONDecoder().decode(AIUsage.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.hasModelBreakdown)
        XCTAssertEqual(decoded.models(for: "2026-10-23").first?.totalTokens, 2)
    }
    // MARK: - Короткая запись токенов

    func testTokensAreShortForLargeAmounts() {
        XCTAssertEqual(AIUsageFormat.tokens(4_720_700_000), "4,7 млрд")
        XCTAssertEqual(AIUsageFormat.tokens(85_100), "85 тыс")
        XCTAssertEqual(AIUsageFormat.tokens(999), "999")
    }

    func testTokensKeepOneDecimalBelowTen() {
        XCTAssertEqual(AIUsageFormat.tokens(2_440_000), "2,4 млн")
        XCTAssertEqual(AIUsageFormat.tokens(1_200_000_000), "1,2 млрд")
    }

    func testWholeAmountsDropTrailingZero() {
        XCTAssertEqual(AIUsageFormat.tokens(500_000_000), "500 млн")
        XCTAssertEqual(AIUsageFormat.tokens(171_000_000), "171 млн")
        XCTAssertEqual(AIUsageFormat.tokens(9_000_000_000), "9 млрд")
    }
}
