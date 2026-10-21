import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class ContextObservabilityTests: XCTestCase {
    func testMissingUsageIsVisibleInsteadOfFreeUsage() throws {
        let json = #"{"window":"24h","since":"2026-10-20T12:00:00Z","trackingSince":"2026-10-21T12:00:00Z","scope":"taskflow_current_key","hasKey":true,"calls":3,"succeeded":1,"failed":1,"running":1,"inputTokens":25,"outputTokens":2,"unknownUsageCalls":2,"scenarios":[],"moneyStatus":"unavailable","balance":null,"cost":null}"#
        let value = try JSONDecoder().decode(JevUsage.self, from: Data(json.utf8))
        XCTAssertEqual(value.unknownUsageCalls, 2)
        XCTAssertTrue(value.coverageText.contains("2"))
        XCTAssertEqual(value.moneyText, "Стоимость и баланс провайдером не предоставлены")
    }
    func testFallbackAndAppliedHaveDifferentMeaning() throws {
        let json = #"{"id":"a","kind":"jev","scenario":"skills","startedAt":"2026-10-21T12:00:00Z","durationMs":8,"status":"ok","reason":"empty_selection_fallback","inputCount":12,"outputCount":12,"details":[]}"#
        let event = try JSONDecoder().decode(ContextObservability.Event.self, from: Data(json.utf8))
        XCTAssertEqual(event.title, "Навыки под задачу")
        XCTAssertEqual(event.outcome, "Ничего не выбрал — оставлены все навыки")
        XCTAssertEqual(event.countsText, "На входе 12 → на выходе 12")
    }
    func testSourceFailureAndTruncationAreExplicit() throws {
        let json = #"{"id":"b","kind":"enricher","scenario":"kb","startedAt":"2026-10-21T12:00:00Z","durationMs":8000,"status":"error","reason":"source_unavailable","details":[]}"#
        let event = try JSONDecoder().decode(ContextObservability.Event.self, from: Data(json.utf8))
        XCTAssertEqual(event.outcome, "Источник недоступен")
        XCTAssertEqual(event.title, "База знаний")
    }
}
