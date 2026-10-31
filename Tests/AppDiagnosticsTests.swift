import XCTest
@testable import TaskFlow

final class AppDiagnosticsTests: XCTestCase {
    func testActiveWorkEndsOnceAndResetDoesNotHideIt() {
        let diagnostics = AppDiagnostics(defaults: nil)
        let queue = diagnostics.begin(.reply)
        XCTAssertEqual(diagnostics.snapshot().activeQueues, 1)
        diagnostics.reset()
        XCTAssertEqual(diagnostics.snapshot().activeQueues, 1)
        diagnostics.end(queue)
        diagnostics.end(queue)
        XCTAssertEqual(diagnostics.snapshot().activeQueues, 0)
        XCTAssertEqual(diagnostics.snapshot().count(.sleeps), 1)
    }

    func testBackgroundCountersAreSeparatedFromForeground() {
        let diagnostics = AppDiagnostics(defaults: nil)
        diagnostics.increment(.ticks, by: 4)
        diagnostics.setBackground(true)
        diagnostics.increment(.ticks, by: 3)
        diagnostics.increment(.messages, by: 2)
        diagnostics.setBackground(false)
        let snapshot = diagnostics.snapshot()
        XCTAssertEqual(snapshot.count(.ticks), 7)
        XCTAssertEqual(snapshot.count(.ticks, backgroundOnly: true), 3)
        XCTAssertEqual(snapshot.count(.messages, backgroundOnly: true), 2)
        XCTAssertFalse(snapshot.background)
        XCTAssertTrue(snapshot.saved.events.contains { $0.background })
    }

    func testPersistenceRestoresCountersButNotStaleActiveWork() throws {
        let name = "AppDiagnosticsTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = AppDiagnostics(defaults: defaults)
        first.increment(.updates, by: 8)
        first.setBackground(true)
        first.increment(.ticks, by: 5)
        first.begin(.reply)
        first.checkpoint()
        let restored = AppDiagnostics(defaults: defaults).snapshot()
        XCTAssertEqual(restored.count(.updates), 8)
        XCTAssertEqual(restored.count(.ticks, backgroundOnly: true), 5)
        XCTAssertEqual(restored.activeQueues, 0)
        XCTAssertFalse(restored.background)
        XCTAssertFalse(restored.saved.events.isEmpty)
    }

    func testJournalIsBoundedAndReportContainsOnlyCounters() {
        let diagnostics = AppDiagnostics(defaults: nil)
        for _ in 0..<100 {
            let queue = diagnostics.begin(.reply)
            diagnostics.end(queue)
        }
        XCTAssertEqual(diagnostics.snapshot().saved.events.count, 80)
        let report = diagnostics.report()
        // С 18.10.2026 отчёт переписан в «диагностику» (docs/2026-10-18-diagnostics-verdicts.md):
        // у каждого счётчика свой заголовок, «всего» и прирост за отсчёт.
        XCTAssertTrue(report.contains("Пробуждения очереди: всего 100"))
        XCTAssertFalse(report.contains("token"))
    }

    func testConcurrentTransportCountersDoNotLoseIncrements() {
        let diagnostics = AppDiagnostics(defaults: nil)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let request = diagnostics.begin(.http)
            diagnostics.increment(.bytes, by: 10)
            diagnostics.end(request)
        }
        XCTAssertEqual(diagnostics.snapshot().count(.requests), 100)
        XCTAssertEqual(diagnostics.snapshot().count(.bytes), 1000)
        XCTAssertEqual(diagnostics.snapshot().active[.http, default: 0], 0)
    }
}
