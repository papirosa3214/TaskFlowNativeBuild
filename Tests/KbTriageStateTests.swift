import XCTest
@testable import TaskFlow

/// Строка «Разбор заметок» в «Состоянии системы» (LOCK-KB-TRIAGE-STATE).
///
/// Владелец 12.10.2026: «посмотри по образцу, как организовано состояние
/// системы с такими автоматами, и точно так же организуй вот это вот» — про
/// сторож разбора заметок на сервере. Клиент показывает его так же, как
/// планировщик: лампа и значение справа.
final class KbTriageStateTests: XCTestCase {
    private func decode(_ json: String) throws -> SystemRunState {
        try JSONDecoder().decode(SystemRunState.self, from: Data(json.utf8))
    }

    /// Полный ответ сервера с блоком разбора.
    func testDecodesKbTriageBlock() throws {
        let state = try decode(#"""
        {"active":true,"enabled":true,"next_scan_at":null,"scan_interval_sec":0,
         "kb_triage":{"active":true,
                      "last_check_at":"2026-10-12T19:25:00.000Z",
                      "last_raised_at":"2026-10-12T18:25:00.000Z",
                      "pending":7,"threshold":20}}
        """#)

        let triage = try XCTUnwrap(state.kbTriage)
        XCTAssertTrue(triage.active)
        XCTAssertEqual(triage.pending, 7)
        XCTAssertEqual(triage.threshold, 20)
        XCTAssertNotNil(triage.lastCheckAt)
        XCTAssertNotNil(triage.lastRaisedAt)
    }

    /// Сервер старой версии поля не отдаёт — экран обязан остаться живым:
    /// тумблеры системы и авторевьюера важнее одной лампы.
    func testOldServerWithoutBlockStillDecodes() throws {
        let state = try decode(#"""
        {"active":true,"enabled":true,"next_scan_at":null,"scan_interval_sec":0}
        """#)

        XCTAssertNil(state.kbTriage)
        XCTAssertTrue(state.active)
    }

    /// Сторож ещё ни разу не заводил задачу — `last_raised_at` пустой.
    /// Это не ошибка: разбирать пока нечего.
    func testNeverRaisedYet() throws {
        let state = try decode(#"""
        {"active":true,"enabled":true,
         "kb_triage":{"active":true,"last_check_at":"2026-10-12T19:25:00.000Z",
                      "last_raised_at":null,"pending":3,"threshold":20}}
        """#)

        let triage = try XCTUnwrap(state.kbTriage)
        XCTAssertNil(triage.lastRaisedAt)
        XCTAssertEqual(triage.pending, 3)
    }

    /// Сторож молчит (сервер не писал отметку) — лампа должна это показать,
    /// а не соврать зелёным.
    func testSilentWatcherHasNoLastCheck() throws {
        let state = try decode(#"""
        {"active":true,"enabled":true,
         "kb_triage":{"active":false,"last_check_at":null,
                      "last_raised_at":null,"pending":0,"threshold":20}}
        """#)

        let triage = try XCTUnwrap(state.kbTriage)
        XCTAssertFalse(triage.active)
        XCTAssertNil(triage.lastCheckAt)
    }
}
