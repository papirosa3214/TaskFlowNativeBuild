import XCTest
@testable import TaskFlow

@MainActor
final class TaskCardLoadingTests: XCTestCase {
    func testOverlappingActivityLoadsShareOneRequestAndLaterReloadStillWorks() async {
        ActivityLoadingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ActivityLoadingProtocol.self]
        let model = TaskFormViewModel(taskID: "loading-card", apiClient: APIClient(session: URLSession(configuration: config)))
        async let first: Void = model.loadActivity()
        async let second: Void = model.loadActivity()
        async let third: Void = model.loadActivity()
        _ = await (first, second, third)
        XCTAssertEqual(ActivityLoadingProtocol.count, 1, "Одновременные обработчики карточки не должны дублировать activity")
        await model.loadActivity()
        XCTAssertEqual(ActivityLoadingProtocol.count, 2, "Завершённый запрос не должен становиться вечным кэшем")
    }
    func testNewActivityRevisionDuringRequestGetsTrailingSnapshot() async {
        let started = expectation(description: "Первый запрос начался")
        ActivityLoadingProtocol.reset(holdFirst: true, started: started)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ActivityLoadingProtocol.self]
        let model = TaskFormViewModel(taskID: "loading-card", apiClient: APIClient(session: URLSession(configuration: config)))
        let first = Task { await model.loadActivity(revision: 0) }
        await fulfillment(of: [started], timeout: 3)
        let revisionEntered = expectation(description: "Новая ревизия передана")
        let second = Task { @MainActor in
            revisionEntered.fulfill()
            await model.loadActivity(revision: 1)
        }
        await fulfillment(of: [revisionEntered], timeout: 3)
        ActivityLoadingProtocol.releaseFirst()
        await first.value
        await second.value
        XCTAssertEqual(ActivityLoadingProtocol.count, 2)
        XCTAssertEqual(model.activity.text, "snapshot-2", "Событие во время загрузки не должно теряться")
    }

    func testInitialReadyDoesNotReloadButEventDuringInitialLoadDoes() {
        var state = TaskCardRefreshState()
        let initial = TaskCardRefreshState.Snapshot(staleRevision: 0, taskRevisions: [:], activityRevision: 0)
        state.begin(initial)
        XCTAssertFalse(state.cardNeedsRefresh(initial, taskIDs: ["card"], ready: true, active: true))
        XCTAssertFalse(state.activityNeedsRefresh(initial, ready: true, active: true))
        state.begin(initial)
        let changed = TaskCardRefreshState.Snapshot(staleRevision: 0, taskRevisions: ["card": 1], activityRevision: 1)
        XCTAssertFalse(state.cardNeedsRefresh(changed, taskIDs: ["card"], ready: false, active: true))
        XCTAssertFalse(state.activityNeedsRefresh(changed, ready: false, active: true))
        XCTAssertTrue(state.cardNeedsRefresh(changed, taskIDs: ["card"], ready: true, active: true))
        XCTAssertTrue(state.activityNeedsRefresh(changed, ready: true, active: true))
        XCTAssertFalse(state.cardNeedsRefresh(changed, taskIDs: ["card"], ready: true, active: true))
        XCTAssertFalse(state.activityNeedsRefresh(changed, ready: true, active: true))
    }

    func testUnrelatedCardAndActivityDoNotReloadCardButChildAndReconnectDo() {
        var state = TaskCardRefreshState()
        var snapshot = TaskCardRefreshState.Snapshot(staleRevision: 0, taskRevisions: [:], activityRevision: 0)
        state.begin(snapshot)
        snapshot.taskRevisions["other"] = 1
        snapshot.activityRevision = 1
        XCTAssertFalse(state.cardNeedsRefresh(snapshot, taskIDs: ["card", "child"], ready: true, active: true))
        XCTAssertTrue(state.activityNeedsRefresh(snapshot, ready: true, active: true))
        snapshot.taskRevisions["child"] = 1
        XCTAssertTrue(state.cardNeedsRefresh(snapshot, taskIDs: ["card", "child"], ready: true, active: true))
        snapshot.staleRevision = 1
        XCTAssertTrue(state.cardNeedsRefresh(snapshot, taskIDs: ["card", "child"], ready: true, active: true))
    }

    func testForegroundRestoresBothSnapshotsExactlyOnce() {
        var state = TaskCardRefreshState()
        let snapshot = TaskCardRefreshState.Snapshot(staleRevision: 0, taskRevisions: [:], activityRevision: 0)
        state.begin(snapshot)
        XCTAssertFalse(state.cardNeedsRefresh(snapshot, taskIDs: ["card"], ready: true, active: false))
        XCTAssertFalse(state.activityNeedsRefresh(snapshot, ready: true, active: false))
        XCTAssertTrue(state.cardNeedsRefresh(snapshot, taskIDs: ["card"], ready: true, active: true))
        XCTAssertTrue(state.activityNeedsRefresh(snapshot, ready: true, active: true))
        XCTAssertFalse(state.cardNeedsRefresh(snapshot, taskIDs: ["card"], ready: true, active: true))
        XCTAssertFalse(state.activityNeedsRefresh(snapshot, ready: true, active: true))
    }

}

private final class ActivityLoadingProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = 0
    nonisolated(unsafe) private static var holdFirst = false
    nonisolated(unsafe) private static var pending: ActivityLoadingProtocol?
    nonisolated(unsafe) private static var started: XCTestExpectation?
    private var number = 0
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests }
    static func reset(holdFirst: Bool = false, started: XCTestExpectation? = nil) {
        lock.lock(); defer { lock.unlock() }
        requests = 0
        self.holdFirst = holdFirst
        self.started = started
        pending = nil
    }
    static func releaseFirst() {
        lock.lock()
        let value = pending
        pending = nil
        holdFirst = false
        lock.unlock()
        value?.complete()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        number = Self.requests
        let hold = Self.holdFirst && number == 1
        if hold { Self.pending = self }
        let started = Self.started
        Self.started = nil
        Self.lock.unlock()
        started?.fulfill()
        if !hold { complete() }
    }
    private func complete() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"text\":\"snapshot-\(number)\",\"actions\":[]}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
