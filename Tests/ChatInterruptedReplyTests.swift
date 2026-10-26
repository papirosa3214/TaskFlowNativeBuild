import XCTest
@testable import TaskFlow

/// Прерванный ответ роли: сервер помечает `stop_reason` и `partial`
/// (карточка b504958a, доработка D1 — уточнение владельца останавливает ход).
/// Клиент только показывает то, что посчитал сервер.
final class ChatInterruptedReplyTests: XCTestCase {
    private func message(_ json: String) throws -> RoleChatMessage {
        try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
    }

    private func roleMessage(stopReason: String?, partial: Bool?) throws -> RoleChatMessage {
        var parts = [
            "\"id\":\"m1\"",
            "\"text\":\"Часть ответа\"",
            "\"chat_id\":\"c1\"",
            "\"from_user_id\":\"role_builder\"",
            "\"is_session_marker\":false",
        ]
        if let stopReason = stopReason { parts.append("\"stop_reason\":\"\(stopReason)\"") }
        if let partial = partial { parts.append("\"partial\":\(partial)") }
        return try message("{" + parts.joined(separator: ",") + "}")
    }

    func testNumericPartialFlagDecodesWithoutLosingMessage() throws {
        let value = try message(#"{"id":"numeric","text":"Partial","is_session_marker":false,"partial":1}"#)
        XCTAssertEqual(value.partial, true)
        XCTAssertEqual(value.interruption, .unknown)
        let complete = try message(#"{"id":"complete","text":"Complete","is_session_marker":false,"partial":0}"#)
        XCTAssertEqual(complete.partial, false)
        XCTAssertNil(complete.interruption)
    }

    func testClarificationStopsTurnAndIsVisible() throws {
        let message = try roleMessage(stopReason: "owner_interrupt", partial: true)
        XCTAssertEqual(message.interruption, .ownerInterrupt)
        XCTAssertEqual(message.partial, true)
        XCTAssertEqual(message.interruption?.label, "Ответ прерван уточнением владельца")
        XCTAssertTrue(message.interruption?.isProblem == true)
    }

    func testFailedTurnIsMarkedSeparately() throws {
        let message = try roleMessage(stopReason: "error", partial: false)
        XCTAssertEqual(message.interruption, .failed)
        XCTAssertEqual(message.interruption?.label, "Ответ прерван ошибкой")
    }

    func testPartialAnswerWithoutReasonIsStillInterrupted() throws {
        let message = try roleMessage(stopReason: nil, partial: true)
        XCTAssertEqual(message.interruption, .unknown)
    }

    func testUnknownServerReasonIsShownAsInterruption() throws {
        let message = try roleMessage(stopReason: "budget_exhausted", partial: false)
        XCTAssertEqual(message.interruption, .other("budget_exhausted"))
        XCTAssertEqual(message.interruption?.label, "Ответ прерван")
    }

    func testOrdinaryReplyHasNoInterruption() throws {
        let message = try roleMessage(stopReason: nil, partial: false)
        XCTAssertNil(message.interruption)
    }

    /// Старый сервер без новых полей должен разбираться как раньше.
    func testLegacyMessageWithoutNewFieldsStillDecodes() throws {
        let message = try roleMessage(stopReason: nil, partial: nil)
        XCTAssertNil(message.stopReason)
        XCTAssertNil(message.partial)
        XCTAssertNil(message.interruption)
    }
}