import XCTest
@testable import TaskFlow

final class AgentTraceTests: XCTestCase {
    func testLiveConversionKeepsServerTimingAndDoesNotInventMissingDates() throws {
        let data = Data(#"{"task_id":"task","subtask_id":"slot","run_id":"run","complete":true,"turn":{"chat_id":"chat","user_id":"role","name":"Role","started_at":"2026-10-10T10:00:00Z","items":[{"kind":"step","id":"with-time","tool":"test","status":"error","started_at":"2026-10-10T10:00:01Z","ended_at":"2026-10-10T10:00:03Z"},{"kind":"step","id":"no-time","tool":"read","status":"done"}]}}"#.utf8)
        let live = try JSONDecoder().decode(TaskLiveTurn.self, from: data)
        let run = try XCTUnwrap(AgentTraceRun.from(live))
        XCTAssertEqual(run.spans.count, 1)
        XCTAssertEqual(run.spans.first?.end?.timeIntervalSince(run.spans[0].start), 2)
    }
    func testReplayStatesIncludeQueueAndError() {
        let start = Date(timeIntervalSince1970: 100)
        let span = AgentTraceSpan(id: "test", label: "Тест", start: start, end: start.addingTimeInterval(5), status: "error")
        XCTAssertEqual(span.state(at: start.addingTimeInterval(-1)), "Ожидает")
        XCTAssertEqual(span.state(at: start.addingTimeInterval(2)), "В работе")
        XCTAssertEqual(span.state(at: start.addingTimeInterval(6)), "Ошибка")
    }
    func testMergeRetainsPreviouslyObservedActions() {
        let now = Date()
        let first = AgentTraceSpan(id: "a", label: "a", start: now, status: "running")
        var run = AgentTraceRun(id: "run", start: now, observedAt: now, complete: false, spans: [first])
        let last = AgentTraceSpan(id: "b", label: "b", start: now.addingTimeInterval(2), end: now.addingTimeInterval(4), status: "done")
        run.merge(AgentTraceRun(id: "run", start: now, observedAt: now.addingTimeInterval(4), complete: true, spans: [last]))
        XCTAssertEqual(run.spans.count, 2)
        XCTAssertTrue(run.complete)
    }
    func testArchivePersistsAndIsolatesSlotsAndBoundsRuns() {
        let name = "AgentTraceTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let archive = AgentTraceArchive(defaults: defaults)
        let runs = (0..<12).map { AgentTraceRun(id: String($0), start: .now, observedAt: .now, complete: true, spans: []) }
        archive.save(runs, scope: "task:one")
        XCTAssertEqual(archive.load(scope: "task:one").count, 10)
        XCTAssertTrue(archive.load(scope: "task:two").isEmpty)
        XCTAssertEqual(archive.load(scope: "task:one").last?.id, "11")
    }
}
