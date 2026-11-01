import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Разбор ответов контракта миссии — сервер TaskFlow (.110, миграции 189–191).
///
/// Тест на данные, а не на вид: клиент не должен падать ни на незнакомом
/// статусе ассерции, ни на отсутствии необязательных полей (старый сервер
/// отдаёт меньше полей, и это не поломка).
final class MissionContractTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// Конверт контракта: ассерции и итог приходят одним ответом.
    private struct ContractEnvelope: Decodable {
        let assertions: [MissionAssertion]
        let outcome: MissionOutcome
    }

    // MARK: - Ассерции

    func testDecodesAssertionEnvelope() throws {
        let json = """
        {
          "assertions": [
            {
              "id": "a1",
              "assertion_id": "VAL-AUTH-001",
              "area": "auth",
              "title": "Вход работает",
              "behavior": "POST /login даёт 200",
              "tool": "browser.mjs",
              "evidence_json": null,
              "status": "passed",
              "claimed_by_slot": "auth"
            }
          ],
          "outcome": {
            "has_contract": true,
            "total": 1,
            "passed": 1,
            "failed": 0,
            "blocked": 0,
            "pending": 0,
            "closed": true,
            "outstanding": []
          }
        }
        """
        let envelope = try decode(ContractEnvelope.self, json)
        XCTAssertEqual(envelope.assertions.count, 1)
        XCTAssertEqual(envelope.assertions.first?.assertionId, "VAL-AUTH-001")
        XCTAssertEqual(envelope.assertions.first?.claimedBySlot, "auth")
        XCTAssertEqual(envelope.assertions.first?.statusEnum, .passed)
        XCTAssertTrue(envelope.outcome.closed)
        XCTAssertTrue(envelope.outcome.outstanding.isEmpty)
    }

    /// Неизвестный статус сервера не должен ломать экран — считаем его
    /// «не проверена».
    func testUnknownStatusFallsBackToPending() {
        XCTAssertEqual(MissionAssertionStatus("passed"), .passed)
        XCTAssertEqual(MissionAssertionStatus("failed"), .failed)
        XCTAssertEqual(MissionAssertionStatus("blocked"), .blocked)
        XCTAssertEqual(MissionAssertionStatus("pending"), .pending)
        XCTAssertEqual(MissionAssertionStatus("что-то новое"), .pending)
        XCTAssertEqual(MissionAssertionStatus(""), .pending)
    }

    /// Необязательные поля (area, tool, claimed_by_slot) могут отсутствовать —
    /// экран обязан показать остальное.
    func testDecodesAssertionWithoutOptionalFields() throws {
        let json = """
        {
          "id": "a2",
          "assertion_id": "VAL-X-002",
          "title": "Без инструмента",
          "behavior": "Проверяется вручную",
          "status": "blocked"
        }
        """
        let assertion = try decode(MissionAssertion.self, json)
        XCTAssertEqual(assertion.assertionId, "VAL-X-002")
        XCTAssertNil(assertion.area)
        XCTAssertNil(assertion.tool)
        XCTAssertNil(assertion.claimedBySlot)
        XCTAssertEqual(assertion.statusEnum, .blocked)
    }

    // MARK: - Итог

    func testDecodesOutcomeWithOutstanding() throws {
        let json = """
        {
          "has_contract": true,
          "total": 12,
          "passed": 9,
          "failed": 1,
          "blocked": 1,
          "pending": 1,
          "closed": false,
          "outstanding": ["VAL-010", "VAL-011", "VAL-012"]
        }
        """
        let outcome = try decode(MissionOutcome.self, json)
        XCTAssertTrue(outcome.hasContract)
        XCTAssertFalse(outcome.closed)
        XCTAssertEqual(outcome.total, 12)
        XCTAssertEqual(outcome.passed, 9)
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(outcome.blocked, 1)
        XCTAssertEqual(outcome.pending, 1)
        XCTAssertEqual(outcome.outstanding.count, 3)
    }

    // MARK: - Журнал

    func testDecodesEventAndKnowsKindTitles() throws {
        let json = """
        {
          "id": "e1",
          "ts": "2026-11-02 01:11:51",
          "kind": "assertion_failed",
          "actor_id": "role_qa",
          "slot_key": "check",
          "payload_json": "{\\"failed\\":[\\"VAL-001\\"]}"
        }
        """
        let event = try decode(MissionEvent.self, json)
        XCTAssertEqual(event.kind, "assertion_failed")
        XCTAssertEqual(event.kindTitle, "Ассерция не пройдена")
        XCTAssertEqual(event.actorId, "role_qa")
        XCTAssertEqual(event.slotKey, "check")
        XCTAssertNotNil(event.payloadJson)
    }

    /// Новый вид события на сервере не должен ломать экран — название
    /// показываем как есть.
    func testUnknownEventKindKeepsRawValue() throws {
        let json = """
        { "id": "e2", "ts": "2026-11-02 01:12:00", "kind": "что-то новое" }
        """
        let event = try decode(MissionEvent.self, json)
        XCTAssertEqual(event.kindTitle, "что-то новое")
    }

    // MARK: - Навыки и покрытие

    func testDecodesMissionSkill() throws {
        let json = """
        {
          "id": "s1",
          "task_id": "t1",
          "role": "analyst",
          "name": "test-skill",
          "description": "Приёмка результата по контракту ассерций.",
          "body": null,
          "source_slot": "check",
          "skill_path": "/home/maksim/taskflow/roles/analyst/skills/test-skill/SKILL.md",
          "created_at": "2026-11-02 01:00:00",
          "released_at": null
        }
        """
        let skill = try decode(MissionSkill.self, json)
        XCTAssertEqual(skill.role, "analyst")
        XCTAssertEqual(skill.name, "test-skill")
        XCTAssertEqual(skill.sourceSlot, "check")
        XCTAssertNil(skill.releasedAt)
    }

    func testDecodesCoverageViolations() throws {
        let json = """
        {
          "ok": false,
          "total": 12,
          "violations": [
            {
              "kind": "uncovered",
              "assertion_id": "VAL-012",
              "slot_key": null,
              "message": "ассерция «VAL-012» не заявлена ни одной работой"
            }
          ]
        }
        """
        let coverage = try decode(AssertionCoverage.self, json)
        XCTAssertFalse(coverage.ok)
        XCTAssertEqual(coverage.total, 12)
        XCTAssertEqual(coverage.violations.first?.assertionId, "VAL-012")
        XCTAssertEqual(coverage.violations.first?.kind, "uncovered")
    }
}
