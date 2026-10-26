import XCTest
@testable import TaskFlow

/// Уточнение роли у владельца из чата (26.10.2026): клиент разбирает вопрос
/// из сообщения и собирает ответ для сервера.
final class RoleQuestionTests: XCTestCase {

    // MARK: - Разбор вопроса из сообщения

    func testMessageDecodesQuestionWithOptionsAndDescription() throws {
        let json = #"{"id":"m1","text":"Нужен выбор","is_session_marker":false,"question":{"id":"q1","status":"open","created_at":"2026-10-26 10:00:00","questions":[{"question":"Что делаем?","header":"Работа","options":[{"label":"Вариант A","description":"быстрее"},{"label":"Вариант B"}],"multi_select":true}]}}"#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        let question = try XCTUnwrap(message.question)
        XCTAssertEqual(question.id, "q1")
        XCTAssertEqual(question.status, "open")
        XCTAssertFalse(question.isAnswered)
        XCTAssertEqual(question.questions.count, 1)
        let item = try XCTUnwrap(question.questions.first)
        XCTAssertEqual(item.question, "Что делаем?")
        XCTAssertEqual(item.header, "Работа")
        XCTAssertTrue(item.multiSelect)
        XCTAssertEqual(item.options.count, 2)
        XCTAssertEqual(item.options.first?.label, "Вариант A")
        XCTAssertEqual(item.options.first?.description, "быстрее")
        XCTAssertNil(item.options.last?.description)
    }

    func testMessageWithoutQuestionKeepsNil() throws {
        let json = #"{"id":"m1","text":"ок","is_session_marker":false}"#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.question)
    }

    func testAnsweredQuestionIsRecognised() throws {
        let json = #"{"id":"m1","text":"ок","is_session_marker":false,"question":{"id":"q1","status":"answered","questions":[],"answer":[{"questionIndex":0,"selected":["A"],"custom":null}]}}"#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        let question = try XCTUnwrap(message.question)
        XCTAssertTrue(question.isAnswered)
        XCTAssertEqual(question.answer?.first?.selected, ["A"])
    }

    /// Сервер может назвать поле `multiSelect` — клиент берёт любое из двух.
    func testMultiSelectAcceptsBothSpellings() throws {
        let camel = #"{"question":"?","options":[],"multiSelect":true}"#
        let snake = #"{"question":"?","options":[],"multi_select":true}"#
        let a = try JSONDecoder().decode(ChatQuestionItem.self, from: Data(camel.utf8))
        let b = try JSONDecoder().decode(ChatQuestionItem.self, from: Data(snake.utf8))
        XCTAssertTrue(a.multiSelect)
        XCTAssertTrue(b.multiSelect)
    }

    /// Битый вопрос не должен рушить сообщение — лента важнее одного поля.
    func testBrokenQuestionDoesNotBreakMessage() throws {
        let json = #"{"id":"m1","text":"ок","is_session_marker":false,"question":{"id":"q1"}}"#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        let question = try XCTUnwrap(message.question)
        XCTAssertEqual(question.questions.count, 0)
    }

    // MARK: - Ответ

    func testAnswerEntryIsEmptyWhenNothingChosenOrWritten() {
        XCTAssertTrue(ChatQuestionAnswerEntry(questionIndex: 0, selected: [], custom: nil).isEmpty)
        XCTAssertTrue(ChatQuestionAnswerEntry(questionIndex: 0, selected: [], custom: "  ").isEmpty)
        XCTAssertFalse(ChatQuestionAnswerEntry(questionIndex: 0, selected: ["A"], custom: nil).isEmpty)
        XCTAssertFalse(ChatQuestionAnswerEntry(questionIndex: 0, selected: [], custom: "своё").isEmpty)
    }

    func testAnswerPayloadEncodesContractKeys() throws {
        let payload = ChatQuestionAnswerPayload(
            answers: [ChatQuestionAnswerEntry(questionIndex: 1, selected: ["A", "B"], custom: "своё")],
            note: "заметка"
        )
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let answers = try XCTUnwrap(json["answers"] as? [[String: Any]])
        let first = try XCTUnwrap(answers.first)
        XCTAssertEqual(first["questionIndex"] as? Int, 1)
        XCTAssertEqual(first["selected"] as? [String], ["A", "B"])
        XCTAssertEqual(first["custom"] as? String, "своё")
        XCTAssertEqual(json["note"] as? String, "заметка")
    }
}
