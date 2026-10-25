import XCTest
@testable import TaskFlow

/// Статусы обращений: получение ответа не означает скрытие карточки.
///
/// Правило живёт в модели, а не во вьюхе: так его видно и в тесте, и в ленте
/// одинаково.
final class RoleChatCoordinationTests: XCTestCase {

    private func coordination(status: String, terminal: Bool, answer: String? = nil) throws -> RoleChatCoordination {
        let json = """
        {
          "requester_name": "Максим",
          "recipient_name": "Архитектор",
          "question": "Уточни границы контракта",
          "status": "\(status)",
          "activity": "Доставлено в работу",
          "created_at": "2026-10-21T10:00:00.000Z",
          "last_activity_at": "2026-10-21T10:00:05.000Z",
          "answer": \(answer.map { "\"\($0)\"" } ?? "null"),
          "terminal": \(terminal)
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(RoleChatCoordination.self, from: json)
    }

    private func message(id: String, status: String, terminal: Bool, answer: String? = nil) throws -> RoleChatMessage {
        let coordinationJSON = """
        {
          "requester_name": "Максим",
          "recipient_name": "Архитектор",
          "question": "Уточни границы контракта",
          "status": "\(status)",
          "activity": "Доставлено в работу",
          "created_at": "2026-10-21T10:00:00.000Z",
          "last_activity_at": "2026-10-21T10:00:05.000Z",
          "answer": \(answer.map { "\"\($0)\"" } ?? "null"),
          "terminal": \(terminal)
        }
        """
        let json = """
        {
          "id": "\(id)",
          "text": "Максим → Архитектор: Доставлено в работу",
          "is_session_marker": false,
          "created_at": "2026-10-21T10:00:00.000Z",
          "coordination": \(coordinationJSON)
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(RoleChatMessage.self, from: json)
    }

    func testDeliveredRowStaysVisible() throws {
        let c = try coordination(status: "delivered", terminal: false)
        XCTAssertFalse(c.isAnswered)
    }

    func testQueuedRowStaysVisible() throws {
        let c = try coordination(status: "queued", terminal: false)
        XCTAssertFalse(c.isAnswered)
    }

    func testAnsweredStatusIsRecognized() throws {
        let c = try coordination(status: "answered", terminal: true, answer: "Готово")
        XCTAssertTrue(c.isAnswered)
    }

    func testErrorRowStaysVisible() throws {
        // Ошибка — не ответ: строка остаётся, в ней видна причина.
        let c = try coordination(status: "error", terminal: true)
        XCTAssertFalse(c.isAnswered)
    }

    func testCancelledRowStaysVisible() throws {
        let c = try coordination(status: "cancelled", terminal: true)
        XCTAssertFalse(c.isAnswered)
    }

    func testMessageWithAnsweredCoordinationIsFinished() throws {
        let m = try message(id: "m1", status: "answered", terminal: true, answer: "Готово")
        XCTAssertTrue(m.isFinishedCoordinationRow)
    }

    func testMessageWithOpenCoordinationIsShownInFeed() throws {
        let m = try message(id: "m2", status: "delivered", terminal: false)
        XCTAssertFalse(m.isFinishedCoordinationRow)
    }

    func testPlainMessageIsNotACoordinationRow() throws {
        let json = """
        {
          "id": "m3",
          "text": "Привет",
          "is_session_marker": false,
          "created_at": "2026-10-21T10:00:00.000Z"
        }
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(RoleChatMessage.self, from: json)
        XCTAssertFalse(m.isFinishedCoordinationRow)
    }
}
