import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Ход шага карточки дельтами (`tasks:live:*`, 27.10.2026): маршрутизатор в
/// клиенте сокета собирает ход и отдаёт экранам привычный снимок; при сбое
/// дельт прогон возвращается на старые полные снимки `tasks:live`.
final class TaskLiveDeltaRouterTests: XCTestCase {
    private func event(_ json: String) -> RoleChatLiveDelta {
        try! JSONDecoder().decode(RoleChatLiveDelta.self, from: Data(json.utf8))
    }
    private let ids = #""chat_id":"t1","task_id":"t1","subtask_id":"s1","run_id":"r1","turn_id":"r1","user_id":"role_builder""#

    @objc func testStartPatchEndShowTurnAndSilenceOldSnapshots() {
        var router = TaskLiveDeltaRouter()
        guard case .show(let started, false) = router.route(event(#"{"type":"tasks:live:start",\#(ids),"name":"Разработчик","started_at":"2026-10-27T10:00:00Z","seq":0,"message_id":null}"#)) else { return XCTFail("start") }
        XCTAssertEqual(started.subtaskID, "s1")
        XCTAssertEqual(router.routeSnapshot(runID: "r1"), .drop)
        XCTAssertEqual(router.routeSnapshot(runID: "other"), .pass)
        guard case .show(let patched, false) = router.route(event(#"{"type":"tasks:live:patch",\#(ids),"seq":1,"ops":[{"op":"item_add","item":{"id":"text-0","kind":"text","text":"Привет"}}]}"#)) else { return XCTFail("patch") }
        XCTAssertEqual(patched.items.map(\.text), ["Привет"])
        guard case .show(let ended, true) = router.route(event(#"{"type":"tasks:live:end",\#(ids),"seq":2,"message_id":null}"#)) else { return XCTFail("end") }
        XCTAssertTrue(ended.isEnded)
        XCTAssertEqual(router.routeSnapshot(runID: "r1"), .drop)
    }

    @objc func testGapFallsBackToOldSnapshots() {
        var router = TaskLiveDeltaRouter()
        _ = router.route(event(#"{"type":"tasks:live:start",\#(ids),"name":"Р","seq":0,"message_id":null}"#))
        XCTAssertEqual(router.route(event(#"{"type":"tasks:live:patch",\#(ids),"seq":3,"ops":[]}"#)), .drop)
        XCTAssertEqual(router.routeSnapshot(runID: "r1"), .pass)
    }

    @objc func testPatchWithoutStartFallsBackToOldSnapshots() {
        var router = TaskLiveDeltaRouter()
        XCTAssertEqual(router.route(event(#"{"type":"tasks:live:patch",\#(ids),"seq":5,"ops":[]}"#)), .drop)
        XCTAssertEqual(router.routeSnapshot(runID: "r1"), .pass)
    }

    @objc func testResetForgetsRuns() {
        var router = TaskLiveDeltaRouter()
        _ = router.route(event(#"{"type":"tasks:live:start",\#(ids),"name":"Р","seq":0,"message_id":null}"#))
        router.reset()
        XCTAssertEqual(router.routeSnapshot(runID: "r1"), .pass)
    }
}
