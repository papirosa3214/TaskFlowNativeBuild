import XCTest
@testable import NewChatCore

/// Точечные тесты очерёдности установки снимка сессии.
/// Симулятор и сеть не нужны: проверяется чистый расчёт `SessionSnapshotGate`.
final class SessionSnapshotGateTests: XCTestCase {
    /// Сеть отвечает не по порядку: более ранний запрос вернулся позже и
    /// раньше затирал более новый снимок.
    func testOlderResponseArrivedLaterIsDropped() {
        var gate = SessionSnapshotGate()
        let first = gate.begin(windowMark: 7)
        let second = gate.begin(windowMark: 7)

        XCTAssertEqual(gate.verdict(second, windowMark: 7), .install)
        gate.markInstalled(second)

        XCTAssertEqual(gate.verdict(first, windowMark: 7), .superseded)
    }

    /// За время запроса пришли события: снимок может быть старше их, но
    /// `seenCursors` после установки счёл бы их принятыми. Ставить нельзя.
    func testSnapshotWithEventsInWindowIsNotInstalled() {
        var gate = SessionSnapshotGate()
        let ticket = gate.begin(windowMark: 3)

        XCTAssertEqual(gate.verdict(ticket, windowMark: 4), .windowDirty)
    }

    /// Обычный путь: окно пустое, снимок ставится один раз, повтор — уже
    /// устаревший ответ.
    func testCleanNewestSnapshotInstallsOnce() {
        var gate = SessionSnapshotGate()
        let ticket = gate.begin(windowMark: 11)

        XCTAssertEqual(gate.verdict(ticket, windowMark: 11), .install)
        gate.markInstalled(ticket)

        XCTAssertEqual(gate.verdict(ticket, windowMark: 11), .superseded)
    }
}
