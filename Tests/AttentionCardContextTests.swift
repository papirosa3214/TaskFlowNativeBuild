import Foundation
import XCTest
@testable import TaskFlow

/// Наводящая строка карточки «Входящих» (LOCK-ATTENTION-CARD-CONTEXT-20261029).
///
/// Сервер отдаёт в каждой задаче строки `hint` — что делать с задачей, не
/// открывая её карточку. Старый сервер этого поля не отдаёт: тогда строки на
/// карточке просто нет, и клиент ломаться не должен.
final class AttentionCardContextTests: XCTestCase {
    private func ticket(_ fields: [String: Any]) throws -> ApiAttentionTicket {
        var json: [String: Any] = ["id": "decision:1", "kind": "decision",
                                   "title": "", "body": "", "created_at": "invalid"]
        json.merge(fields) { _, new in new }
        return try JSONDecoder().decode(ApiAttentionTicket.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    func testQuestionPreviewShowsOnlyTheFirstQuestionAndTheAnswerCount() throws {
        let item = try ticket(["kind": "question", "title": "Какой проект выбрать?",
            "body": "Второй вопрос\nТретий вопрос", "context_title": "Длинное название задачи",
            "chat_id": "chat", "question": ["id": "q", "status": "open", "questions": [
                ["question": "Какой проект выбрать?"], ["question": "Когда начать?"],
                ["question": "Кто проверит?"]]]])
        XCTAssertEqual(item.cardTitle, "Нужен ответ")
        XCTAssertEqual(item.cardSummary, "Какой проект выбрать?")
        XCTAssertEqual(item.sourceTitle, "В чате")
        XCTAssertEqual(item.actionTitle, "Ответить на 3 вопроса")
    }

    func testApprovalPreviewUsesRationaleRatherThanRepeatingItsTitle() throws {
        let item = try ticket(["id": "plan:1", "kind": "approval", "title": "Согласовать план работы",
            "body": "Сначала резервная копия, затем перенос данных.\nПодробности ниже",
            "task_id": "task", "context_title": "Название задачи"])
        XCTAssertEqual(item.cardTitle, "Согласовать план")
        XCTAssertEqual(item.cardSummary, "Сначала резервная копия, затем перенос данных.")
        XCTAssertEqual(item.sourceTitle, "По задаче")
    }

    func testBlockedPreviewKeepsTheActualRequestedAction() throws {
        let item = try ticket(["title": "**Нужен перезапуск сервера.**\nДлинный разбор ошибки",
                               "body": "Нужно ваше решение для продолжения работы", "task_id": "task"])
        XCTAssertEqual(item.cardTitle, "Ход заблокирован")
        XCTAssertEqual(item.cardSummary, "Нужен перезапуск сервера.")
        XCTAssertEqual(item.actionTitle, "Разобрать блокировку")
        XCTAssertEqual(item.action, .task("task"))
    }

    func testSummaryDoesNotInventAServiceActionOrRepeatTaskTitle() throws {
        let item = try ticket(["title": "Очень длинное название задачи", "context_title": "Очень длинное название задачи",
            "body": "Нужно ваше решение для продолжения работы", "task_id": "task"])
        XCTAssertNil(item.cardSummary)
        XCTAssertEqual(item.cardTitle, "Ход заблокирован")
    }

    func testPreviewIsBoundedAndPreservesFullSourceText() throws {
        let text = String(repeating: "Нужен доступ к сервису. ", count: 100)
        let item = try ticket(["title": text, "task_id": "task"])
        XCTAssertLessThanOrEqual(item.cardSummary?.count ?? 0, 160)
        XCTAssertTrue(item.cardSummary?.hasSuffix("…") == true)
        XCTAssertEqual(item.title, text)
    }

    func testChangedPlanAndUnknownKindHaveHonestLabels() throws {
        let changed = try ticket(["id": "plan-op:1", "kind": "approval", "task_id": "task"])
        XCTAssertEqual(changed.cardTitle, "Изменить план")
        let unknown = try ticket(["kind": "future-kind", "title": "Проверьте результат", "chat_id": "chat"])
        XCTAssertEqual(unknown.cardTitle, "Нужно решение")
        XCTAssertEqual(unknown.cardSummary, "Проверьте результат")
        XCTAssertEqual(unknown.actionTitle, "Открыть чат")
        let unknownTask = try ticket(["kind": "future-kind", "task_id": "task"])
        XCTAssertEqual(unknownTask.actionTitle, "Открыть задачу")
    }

    func testFormattingDoesNotCorruptAServiceName() throws {
        let item = try ticket(["title": "Нужен доступ к `taskflow_server`.", "task_id": "task"])
        XCTAssertEqual(item.cardSummary, "Нужен доступ к taskflow_server.")
    }

    func testMalformedQuestionOpensChatInsteadOfAnEmptyAnswerForm() throws {
        let ticket = try JSONDecoder().decode(ApiAttentionTicket.self, from: Data(#"{"id":"question:q","kind":"question","title":"Вопрос","body":"","chat_id":"chat","created_at":"invalid","question":{"id":"q","status":"open","questions":[]}}"#.utf8))
        XCTAssertEqual(ticket.action, .chat("chat"))
        XCTAssertNil(ticket.createdDate)
    }
    func testTicketDateIsUTCAndInvalidDateIsAbsent() throws {
        let ticket = try JSONDecoder().decode(ApiAttentionTicket.self, from: Data(#"{"id":"x","kind":"decision","title":"Решение","body":"","created_at":"2026-10-30 10:00:00"}"#.utf8))
        XCTAssertEqual(ticket.createdDate?.timeIntervalSince1970, 1793354400)
    }


    func testTicketsAreIndependentFromLegacyGroupsAndKeepDistinctIDs() throws {
        let feed = try JSONDecoder().decode(ApiAttention.self, from: Data(#"{"ok":true,"groups":[],"tickets":[{"id":"question:q1","kind":"question","title":"Продолжать?","body":"","chat_id":"chat","created_at":"2026-10-30 10:00:00"},{"id":"question:q2","kind":"question","title":"Какой проект?","body":"","chat_id":"chat","created_at":"2026-10-30 10:01:00"}]}"#.utf8))
        XCTAssertEqual(feed.tickets?.map(\.id), ["question:q1", "question:q2"])
        XCTAssertEqual(feed.tickets?.first?.action, .chat("chat"))
    }

    func testOldServerIsUnsupportedRatherThanAnEmptyInbox() throws {
        let feed = try JSONDecoder().decode(ApiAttention.self, from: Data(#"{"ok":true,"groups":[]}"#.utf8))
        XCTAssertNil(feed.tickets)
    }

    func testQuestionUsesOriginalAnswerFormAndPlanUsesTask() throws {
        let question = try JSONDecoder().decode(ApiAttentionTicket.self, from: Data(#"{"id":"question:q","kind":"question","title":"Продолжать?","body":"","chat_id":"chat","task_id":"task","created_at":"2026-10-30 10:00:00","question":{"id":"q","status":"open","questions":[{"question":"Продолжать?","options":[{"label":"Да"},{"label":"Нет"}]}]}}"#.utf8))
        XCTAssertEqual(question.action, .answer(chatID: "chat", questionID: "q"))
        let plan = try JSONDecoder().decode(ApiAttentionTicket.self, from: Data(#"{"id":"plan:p","kind":"approval","title":"Согласовать план","body":"","task_id":"task","created_at":"2026-10-30 10:00:00"}"#.utf8))
        XCTAssertEqual(plan.action, .task("task"))
    }

    func testMissingDestinationDoesNotOfferAFalseAction() throws {
        let ticket = try JSONDecoder().decode(ApiAttentionTicket.self, from: Data(#"{"id":"x","kind":"decision","title":"Нужно решение","body":"","task_id":"  ","created_at":"2026-10-30 10:00:00"}"#.utf8))
        XCTAssertNil(ticket.action)
    }
    private func decode(_ json: String) throws -> ApiAttentionTask {
        try JSONDecoder().decode(ApiAttentionTask.self, from: Data(json.utf8))
    }

    func testDecodesHintFromServer() throws {
        let task = try decode(
            #"{"id":"t1","title":"Проверить окно","project":"TaskFlow","role":"Лайф-тестировщик","age_seconds":60,"overdue":false,"hint":"Проверка заблокирована: нужно решение владельца."}"#
        )
        XCTAssertEqual(task.hint, "Проверка заблокирована: нужно решение владельца.")
        XCTAssertEqual(task.hintLine, "Проверка заблокирована: нужно решение владельца.")
    }

    func testOldServerWithoutHintStillDecodes() throws {
        let task = try decode(
            #"{"id":"t2","title":"Проверить окно","project":null,"role":null,"age_seconds":null,"overdue":false}"#
        )
        XCTAssertNil(task.hint)
        XCTAssertNil(task.hintLine)
    }

    func testEmptyHintIsNotDrawn() throws {
        let task = try decode(#"{"id":"t3","title":"Проверить окно","hint":"   "}"#)
        XCTAssertNil(task.hintLine)
    }

    func testHintKeepsInnerLineBreaks() throws {
        // Переводы строк склеивает сервер; клиент только убирает края.
        let task = try decode(#"{"id":"t4","title":"Проверить окно","hint":"  Нужен ваш ответ: уточните исполнителя  "}"#)
        XCTAssertEqual(task.hintLine, "Нужен ваш ответ: уточните исполнителя")
    }

    func testDecodesFieldsForTheRowLikeOtherLists() throws {
        let task = try decode(
            #"{"id":"t5","title":"Проверить окно","project":"TaskFlow","role":"Лайф-тестировщик","age_seconds":60,"overdue":false,"hint":"Проверка заблокирована.","role_id":"role_qa","priority":2,"subtask_total":6,"subtask_done":4}"#
        )
        XCTAssertEqual(task.role_id, "role_qa")
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(task.subtask_total, 6)
        XCTAssertEqual(task.subtask_done, 4)
    }

    func testOldServerWithoutNewFieldsStillDecodes() throws {
        let task = try decode(
            #"{"id":"t6","title":"Проверить окно","project":null,"role":null,"age_seconds":null,"overdue":false}"#
        )
        XCTAssertNil(task.role_id)
        XCTAssertNil(task.priority)
        XCTAssertNil(task.subtask_total)
        XCTAssertNil(task.subtask_done)
        XCTAssertNil(task.roleInitials)
    }

    func testRoleInitialsTakeFirstLettersOfTwoWords() throws {
        let task = try decode(#"{"id":"t7","title":"Проверить окно","role":"Лайф-тестировщик","role_id":"role_qa"}"#)
        XCTAssertEqual(task.roleInitials, "ЛТ")
    }
}
