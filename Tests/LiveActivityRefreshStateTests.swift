import XCTest
@testable import TaskFlow

/// Обновление списка действий не должно обгонять события: окно живого хода
/// перерисовывалось раз в секунду и уводило прокрутку наверх (владелец
/// 25.10.2026).
final class LiveActivityRefreshStateTests: XCTestCase {
    private let start = ContinuousClock.Instant.now

    func testEventMarksListStale() {
        let state = LiveActivityRefreshState()
        XCTAssertFalse(state.isDirty)

        state.markDirty()
        XCTAssertTrue(state.isDirty)
    }

    func testStaleListIsTakenOnce() {
        let state = LiveActivityRefreshState()
        state.markDirty()

        XCTAssertTrue(state.takeDirty(now: start))
        XCTAssertFalse(state.takeDirty(now: start + .seconds(30)))
        XCTAssertFalse(state.isDirty)
    }

    func testNextEventWaitsForInterval() {
        let state = LiveActivityRefreshState()
        state.markDirty()
        XCTAssertTrue(state.takeDirty(now: start))

        // Событие пришло сразу после обновления — обновляться раньше времени
        // нельзя, но флаг протухания обязан пережить паузу.
        state.markDirty()
        XCTAssertFalse(state.takeDirty(now: start + .seconds(1)))
        XCTAssertTrue(state.isDirty)

        XCTAssertTrue(state.takeDirty(now: start + .seconds(2)))
    }

    func testBurstOfEventsCostsOneRefresh() {
        let state = LiveActivityRefreshState()
        for _ in 0..<20 { state.markDirty() }

        XCTAssertTrue(state.takeDirty(now: start))
        XCTAssertFalse(state.takeDirty(now: start + .seconds(1)))
    }
}
