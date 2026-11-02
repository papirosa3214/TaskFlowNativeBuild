import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Разбор сводки по исполнителям — сервер TaskFlow (.110, PR #53).
///
/// Тест на данные, а не на вид: телефон ничего не разбирает (правка владельца
/// 02.11.2026) — сервер отдаёт человеческий текст, клиент только рисует.
/// Проверяем, что имена полей совпадают с контрактом и что направление
/// сообщения («вы → роль» / «роль → вы») читается правильно.
final class ExecutorSummaryTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private let sample = """
    {
      "task_id": "task_1",
      "task_title": "Починить прокси",
      "generated_at": "2026-11-02T05:00:00.000Z",
      "orchestrator": {
        "role": "code_orchestrator",
        "title": "Оркестратор",
        "executor_id": "role_code_orchestrator",
        "slot_id": "sub_orch",
        "addressable": true,
        "address_block_reason": null
      },
      "executors": [
        {
          "subtask_id": "sub_1",
          "plan_node_key": "work_1",
          "title": "Восстановить рабочий прокси",
          "role": "infra_engineer",
          "role_title": "Инженер .110",
          "executor_id": "role_infra_engineer",
          "state": "working",
          "state_title": "Идёт работа",
          "status_text": "Шаг выполняет Инженер .110",
          "cause": "active_run",
          "done": false,
          "skipped": false,
          "waiting_for": ["Ответ владельца"],
          "notes": "Поднят новый туннель",
          "attempt": { "started_at": "2026-11-02 04:50:00", "ended_at": null, "outcome": null },
          "metrics": { "age_seconds": 600, "attempts_in_window": 1, "heartbeat_age": 5 },
          "addressable": true,
          "address_block_reason": null,
          "pending_messages": 2,
          "discussion_id": null,
          "questions": [
            {
              "id": "q_1",
              "chat_id": "chat_1",
              "role_key": "infra_engineer",
              "role_title": "Инженер .110",
              "created_at": "2026-11-02 04:55:00",
              "deadline_at": null,
              "payload": {
                "questions": [
                  {
                    "question": "Какой бэкенд выбрать?",
                    "header": "Бэкенд",
                    "options": [
                      { "label": "Прокси", "description": "через 10811" },
                      { "label": "Прямой" }
                    ],
                    "multiSelect": false
                  }
                ],
                "note": "Ответь в чате"
              }
            }
          ],
          "messages": [
            { "id": "m_1", "text": "Проверь, почему не поднялся", "created_at": "2026-11-02 04:52:00", "direction": "owner_to_role" },
            { "id": "m_2", "text": "Поднял новый туннель", "created_at": "2026-11-02 04:53:00", "direction": "role_to_owner" }
          ]
        }
      ],
      "pending_questions": []
    }
    """

    func testDecodesSummaryAndExecutor() throws {
        let summary = try decode(TaskExecutorSummary.self, sample)
        XCTAssertEqual(summary.taskId, "task_1")
        XCTAssertEqual(summary.taskTitle, "Починить прокси")
        XCTAssertEqual(summary.executors.count, 1)

        let executor = try XCTUnwrap(summary.executors.first)
        XCTAssertEqual(executor.subtaskId, "sub_1")
        XCTAssertEqual(executor.planNodeKey, "work_1")
        XCTAssertEqual(executor.role, "infra_engineer")
        XCTAssertEqual(executor.roleTitle, "Инженер .110")
        XCTAssertEqual(executor.executorId, "role_infra_engineer")
        XCTAssertEqual(executor.state, "working")
        XCTAssertEqual(executor.stateTitle, "Идёт работа")
        XCTAssertEqual(executor.statusText, "Шаг выполняет Инженер .110")
        XCTAssertEqual(executor.cause, "active_run")
        XCTAssertEqual(executor.waitingFor, ["Ответ владельца"])
        XCTAssertEqual(executor.notes, "Поднят новый туннель")
        XCTAssertTrue(executor.addressable)
        XCTAssertNil(executor.addressBlockReason)
        XCTAssertEqual(executor.pendingMessages, 2)
        XCTAssertFalse(executor.done)
        XCTAssertFalse(executor.skipped)
    }

    func testDecodesAttemptAndMetrics() throws {
        let summary = try decode(TaskExecutorSummary.self, sample)
        let executor = try XCTUnwrap(summary.executors.first)
        XCTAssertEqual(executor.attempt.startedAt, "2026-11-02 04:50:00")
        XCTAssertNil(executor.attempt.endedAt)
        XCTAssertNil(executor.attempt.outcome)
        XCTAssertEqual(executor.metrics.ageSeconds, 600)
        XCTAssertEqual(executor.metrics.attemptsInWindow, 1)
        XCTAssertEqual(executor.metrics.heartbeatAge, 5)
    }

    func testDecodesOrchestrator() throws {
        let summary = try decode(TaskExecutorSummary.self, sample)
        XCTAssertEqual(summary.orchestrator.role, "code_orchestrator")
        XCTAssertEqual(summary.orchestrator.title, "Оркестратор")
        XCTAssertEqual(summary.orchestrator.executorId, "role_code_orchestrator")
        XCTAssertEqual(summary.orchestrator.slotId, "sub_orch")
        XCTAssertTrue(summary.orchestrator.addressable)
    }

    func testDecodesQuestionWithOptions() throws {
        let summary = try decode(TaskExecutorSummary.self, sample)
        let question = try XCTUnwrap(summary.executors.first?.questions.first)
        XCTAssertEqual(question.id, "q_1")
        XCTAssertEqual(question.chatId, "chat_1")
        XCTAssertEqual(question.roleKey, "infra_engineer")
        let payload = try XCTUnwrap(question.payload)
        XCTAssertEqual(payload.questions.count, 1)
        XCTAssertEqual(payload.questions.first?.question, "Какой бэкенд выбрать?")
        XCTAssertEqual(payload.questions.first?.options.count, 2)
        XCTAssertEqual(payload.questions.first?.options.first?.label, "Прокси")
        XCTAssertEqual(payload.questions.first?.options.first?.description, "через 10811")
        XCTAssertFalse(payload.questions.first?.multiSelect ?? true)
    }

    func testMessageDirectionTellsWhoSpoke() throws {
        let summary = try decode(TaskExecutorSummary.self, sample)
        let messages = try XCTUnwrap(summary.executors.first?.messages)
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[0].isFromOwner)
        XCTAssertFalse(messages[1].isFromOwner)
        XCTAssertEqual(messages[0].text, "Проверь, почему не поднялся")
    }

    /// Ответ без вопросов и без переписки — пустой слот не должен ломать окно.
    func testDecodesExecutorWithoutQuestionsAndMessages() throws {
        let json = """
        {
          "task_id": "task_2",
          "task_title": "Пусто",
          "generated_at": "2026-11-02T05:00:00.000Z",
          "orchestrator": {
            "role": "code_orchestrator",
            "title": "Оркестратор",
            "executor_id": "role_code_orchestrator",
            "slot_id": null,
            "addressable": false,
            "address_block_reason": "нет слота оркестратора"
          },
          "executors": [
            {
              "subtask_id": "sub_2",
              "plan_node_key": null,
              "title": "Шаг",
              "role": null,
              "role_title": null,
              "executor_id": null,
              "state": "unknown",
              "state_title": "Состояние неизвестно",
              "status_text": "Состояние неизвестно",
              "cause": "unknown",
              "done": false,
              "skipped": false,
              "waiting_for": [],
              "notes": null,
              "attempt": { "started_at": null, "ended_at": null, "outcome": null },
              "metrics": { "age_seconds": 0, "attempts_in_window": 0, "heartbeat_age": 0 },
              "addressable": false,
              "address_block_reason": "роль не назначена",
              "pending_messages": 0,
              "discussion_id": null,
              "questions": [],
              "messages": []
            }
          ],
          "pending_questions": []
        }
        """
        let summary = try decode(TaskExecutorSummary.self, json)
        XCTAssertNil(summary.orchestrator.slotId)
        XCTAssertFalse(summary.orchestrator.addressable)
        let executor = try XCTUnwrap(summary.executors.first)
        XCTAssertTrue(executor.questions.isEmpty)
        XCTAssertTrue(executor.messages.isEmpty)
        XCTAssertNil(executor.role)
        XCTAssertEqual(executor.addressBlockReason, "роль не назначена")
    }
}
