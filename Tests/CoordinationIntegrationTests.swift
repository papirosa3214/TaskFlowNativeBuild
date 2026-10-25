import XCTest
@testable import TaskFlow

final class CoordinationIntegrationTests: XCTestCase {
    private func resolution(id: String? = "s1", version: String = "2.0.0", links: String = "[]", planKey: String? = nil) throws -> APIClient.CoordinationResolution {
        let json = """
        {"contract_version":"\(version)","generated_at":"2026-10-26T00:00:00Z","subtask_id":\(id.map { "\"\($0)\"" } ?? "null"),"task_id":"t1","plan_node_key":\(planKey.map { "\"\($0)\"" } ?? "null"),"role":"builder","cause":"step_stalled","action":"replace_attempt","assignee":{"kind":"role","key":"builder"},"deadline_hint":null,"checked_after":null,"evidence":[],"metrics":{"age_seconds":0,"attempts_in_window":0,"heartbeat_age":0},"notes":"Шаг ожидает решения","links":\(links)}
        """
        return try JSONDecoder().decode(APIClient.CoordinationResolution.self, from: Data(json.utf8))
    }

    func testActualServerLinksDecode() throws {
        _ = try resolution(links: #"[{"href":"/api/subtasks/s1/restart","rel":"replace","note":"повторить"}]"#)
    }
    func testSkippedStepDoesNotOfferRestart() throws {
        let json = #"{"contract_version":"2.0.0","generated_at":"2026-10-26T00:00:00Z","subtask_id":"s1","task_id":"t1","plan_node_key":"builder","role":"builder","cause":"step_stalled","action":"replace_attempt","assignee":{"kind":"role","key":"builder"},"deadline_hint":null,"checked_after":null,"evidence":[],"metrics":{"age_seconds":0,"attempts_in_window":0,"heartbeat_age":0},"notes":null,"links":[],"skipped":true}"#
        let r = try JSONDecoder().decode(APIClient.CoordinationResolution.self, from: Data(json.utf8))
        XCTAssertFalse(r.canRestartStep)
        XCTAssertNil(r.controlLabel)
        XCTAssertEqual(r.displayStatus, "Шаг пропущен")
    }
    func testTaskLevelResolutionAcceptsNullSubtask() throws {
        _ = try resolution(id: nil)
    }
    func testServerActionNamesMatch() {
        XCTAssertEqual(CoordinationAction(rawValue: "replace_attempt"), .replaceAttempt)
        XCTAssertEqual(CoordinationAction(rawValue: "switch_provider"), .switchProvider)
        XCTAssertEqual(CoordinationAction(rawValue: "no_action"), .noAction)
    }
    func testDisappearedNodeStopsExposingOldAction() throws {
        let r = try resolution()
        MainActor.assumeIsolated {
            let state = CoordinationState()
            state.apply(resolutions: [r], contractVersion: "2.0.0")
            state.apply(resolutions: [], contractVersion: "2.0.0")
            XCTAssertEqual(state.nodes.count, 1)
            XCTAssertNil(state.nodes[0].resolution)
        }
    }
    func testVersionMismatchRecoversWhenCompatibleDataReturns() throws {
        let old = try resolution(version: "3.0.0"), good = try resolution()
        MainActor.assumeIsolated {
            let state = CoordinationState()
            state.apply(resolutions: [old], contractVersion: "3.0.0")
            state.apply(resolutions: [good], contractVersion: "2.0.0")
            XCTAssertEqual(state.loadState, .loaded)
        }
    }
    func testServerEnvelopeAndOptionalReadableFields() throws {
        let json = #"{"task_id":"t1","resolutions":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(APIClient.TaskResolutions.self, from: Data(json.utf8)).items, [])
        var r = try resolution(planKey: "builder")
        XCTAssertTrue(r.canRestartStep)
        r.done = true
        XCTAssertNil(r.controlLabel)
        XCTAssertFalse(r.canRestartStep)
        r.title = "Реальная реализация"
        XCTAssertEqual(r.displayTitle, "Реальная реализация")
        XCTAssertEqual(r.displayStatus, "Шаг завершён")
    }
    func testDuplicateNodeDoesNotCreateTwoActionTargets() throws {
        let r = try resolution()
        MainActor.assumeIsolated {
            let state = CoordinationState()
            state.apply(resolutions: [r, r], contractVersion: "2.0.0")
            XCTAssertEqual(state.nodes.count, 1)
        }
    }
    func testTaskCoordinationHintCompletes() throws {
        MainActor.assumeIsolated {
            let defaults = UserDefaults(suiteName: "coordination-hint-test")!
            defaults.removePersistentDomain(forName: "coordination-hint-test")
            let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.taskCoordination])
            center.isEnabled = true
            center.report(anchor: HintAnchorID.taskCoordination, frame: CGRect(x: 1, y: 1, width: 44, height: 44))
            XCTAssertEqual(center.active?.step, "step")
            center.next()
            XCTAssertTrue(center.completed.contains("task-coordination"))
            defaults.removePersistentDomain(forName: "coordination-hint-test")
        }
    }

}


#if COORDINATION_TRANSPORT_FIXTURE
/// Executes the real API methods with deterministic responses; no running server.
final class CoordinationTransportTests: XCTestCase {
    private func payload(done: Bool = false, version: String = "2.0.0") -> Data {
        Data("""
        {"task_id":"t1","resolutions":[{"contract_version":"\(version)","generated_at":"2026-10-26T00:00:00Z","subtask_id":"s1","task_id":"t1","plan_node_key":"builder","role":"builder","cause":"step_stalled","action":"replace_attempt","assignee":{"kind":"role","key":"builder"},"deadline_hint":null,"checked_after":null,"evidence":[],"metrics":{"age_seconds":0,"attempts_in_window":0,"heartbeat_age":0},"notes":null,"links":[],"title":"Реальный шаг","done":\(done)}]}
        """.utf8)
    }
    func testFetchUsesServerEnvelopeInOneRequest() {
        APIClient.responses = [payload()]; APIClient.paths = []
        let finished = expectation(description: "fetched")
        Task {
            do {
                let items = try await APIClient().fetchTaskResolutions(taskId: "t1")
                XCTAssertEqual(items.first?.displayTitle, "Реальный шаг")
                XCTAssertEqual(APIClient.paths, ["/coordination/tasks/t1/resolve"])
            } catch { XCTFail(String(describing: error)) }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }
    func testMalformedResponseDoesNotTriggerSecondRequest() {
        APIClient.responses = [Data("{}".utf8), payload()]; APIClient.paths = []
        let finished = expectation(description: "failed")
        Task {
            do { _ = try await APIClient().fetchTaskResolutions(taskId: "t1"); XCTFail("Expected decoder failure") }
            catch { XCTAssertEqual(APIClient.paths.count, 1) }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }
    func testRestartRechecksAndWritesOnlySelectedStep() throws {
        let selected = try JSONDecoder().decode(APIClient.TaskResolutions.self, from: payload()).items[0]
        APIClient.responses = [payload(), Data(#"{"ok":true}"#.utf8)]; APIClient.paths = []
        let finished = expectation(description: "restarted")
        Task {
            do {
                try await APIClient().restartCoordinationStep(selected, reason: "  Повторить проверку  ")
                XCTAssertEqual(APIClient.paths, ["/coordination/tasks/t1/resolve", "/subtasks/s1/restart"])
                let body = try JSONSerialization.jsonObject(with: APIClient.lastBody!) as! [String:String]
                XCTAssertEqual(body, ["role":"builder","reason":"Повторить проверку"])
            } catch { XCTFail(String(describing: error)) }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }
    func testFinishedStepCannotRestartFromStaleConfirmation() throws {
        let selected = try JSONDecoder().decode(APIClient.TaskResolutions.self, from: payload()).items[0]
        APIClient.responses = [payload(done: true)]; APIClient.paths = []
        let finished = expectation(description: "blocked")
        Task {
            do { try await APIClient().restartCoordinationStep(selected, reason: "Проверка"); XCTFail("Must reject stale action") }
            catch { XCTAssertEqual(APIClient.paths, ["/coordination/tasks/t1/resolve"]) }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }
}
#endif
