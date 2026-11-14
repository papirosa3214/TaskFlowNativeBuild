import XCTest
@testable import NewChatCore

/// Точечные тесты окна снимка сессии.
///
/// Окно — метка, которую двигают ВСЕ пути, меняющие состояние: живые события
/// и догнанные после переподключения (включая замену состояния по
/// `resetRequired`). Снимок ставится только при пустом окне
/// (`SessionSnapshotGate`), поэтому неотмеченное восстановление давало
/// установку старого снимка поверх восстановленного состояния.
///
/// Симулятор и сеть не нужны: проверяется чистый расчёт `SessionEventWindow`.
final class SessionEventWindowTests: XCTestCase {
    private func event(_ cursor: String, session: String = "root", type: String = "assistant_text_delta") -> SessionEventEnvelope {
        SessionEventEnvelope(cursor: cursor, sessionId: session, type: type, timestamp: "t", payload: [:])
    }

    /// Догнанные после переподключения куски применяются напрямую к состоянию
    /// и обязаны закрыть окно: иначе снимок, запрос которого начат раньше,
    /// встанет поверх восстановленного и съест их через `seenCursors`.
    func testReconnectEventsMakePendingSnapshotWindowDirty() {
        var window = SessionEventWindow()
        var gate = SessionSnapshotGate()
        let ticket = gate.begin(windowMark: window.mark)

        let fresh = SessionEventWindow.freshEvents(
            [event("c1"), event("c2")], sessionID: "root", seenCursors: []
        )
        window.noteFresh(fresh.count)

        XCTAssertEqual(fresh.count, 2)
        XCTAssertEqual(window.mark, 2)
        XCTAssertEqual(gate.verdict(ticket, windowMark: window.mark), .windowDirty)
    }

    /// `resetRequired`: состояние заменяется целиком, поэтому окно грязное даже
    /// когда новых событий нет — снимок, начатый до замены, всё равно старше.
    func testResetRequiredMarksWindowDirtyWithoutEvents() {
        var window = SessionEventWindow()
        var gate = SessionSnapshotGate()
        let ticket = gate.begin(windowMark: window.mark)

        window.noteReset()

        XCTAssertEqual(gate.verdict(ticket, windowMark: window.mark), .windowDirty)
    }

    /// Сервер после переподключения пересылает уже принятые куски: повтор не
    /// меняет состояние и не должен выбрасывать снимок — иначе две попытки
    /// сгорают на повторах и свежий снимок не ставится вовсе.
    func testAlreadySeenAndForeignEventsDoNotMoveMark() {
        var window = SessionEventWindow()
        let seen: Set<String> = ["c1"]

        let isNewDuplicate = window.noteLive(event("c1"), activeSessionID: "root", seenCursors: seen)
        let isNewForeign = window.noteLive(event("c9", session: "child"), activeSessionID: "root", seenCursors: seen)

        XCTAssertFalse(isNewDuplicate)
        XCTAssertFalse(isNewForeign)
        XCTAssertEqual(window.mark, 0)
    }

    /// Новое событие открытой сессии окно закрывает и считается один раз.
    func testFreshLiveEventMovesMarkOnce() {
        var window = SessionEventWindow()
        var gate = SessionSnapshotGate()
        let ticket = gate.begin(windowMark: window.mark)

        XCTAssertTrue(window.noteLive(event("c1"), activeSessionID: "root", seenCursors: []))
        XCTAssertFalse(window.noteLive(event("c1"), activeSessionID: "root", seenCursors: ["c1"]))
        XCTAssertEqual(window.mark, 1)
        XCTAssertEqual(gate.verdict(ticket, windowMark: window.mark), .windowDirty)
    }

    /// Догнанный набор чистится от повторов и чужих сессий: применяются и
    /// считаются только реально новые куски открытой сессии.
    func testFreshEventsFiltersDuplicatesAndForeignSessions() {
        let fresh = SessionEventWindow.freshEvents(
            [event("c1"), event("c1"), event("c2"), event("x1", session: "child")],
            sessionID: "root",
            seenCursors: ["c1"]
        )

        XCTAssertEqual(fresh.map(\.cursor), ["c2"])
    }
}
