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
}
