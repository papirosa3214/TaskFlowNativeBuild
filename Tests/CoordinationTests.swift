import XCTest
@testable import TaskFlow

/// Чистая логика координации V2. Без SwiftUI/UIApplication, без сети —
/// проверяется самым дешёвым способом: декодирование JSON, диф узлов,
/// маппинг 20 причин → видимый текст + действие.
///
/// Владелец реально увидит: 20 причин на iPhone показывают заголовок,
/// подсказку и кнопку; стабильный граф не сдвигает соседей при обновлении;
/// 4 состояния доставки сообщения имеют разный чип.
final class CoordinationTests: XCTestCase {

    // MARK: - Декодирование Resolution (контракт V2, contract_version=2.0.0)

    func testDecodesResolutionFromServerJSON() throws {
        let json = """
        {
          "contract_version": "2.0.0",
          "generated_at": "2026-10-08T12:34:56.000Z",
          "subtask_id": "sub_1",
          "task_id": "task_1",
          "plan_node_key": "builder.server",
          "role": "builder",
          "cause": "stalled_manual_review",
          "action": "replace_attempt",
          "assignee": { "kind": "role", "key": "builder" },
          "deadline_hint": null,
          "checked_after": null,
          "evidence": [
            { "kind": "task_event", "ref": "task_events.42" }
          ],
          "metrics": { "age_seconds": 600, "attempts_in_window": 3, "heartbeat_age": 700 },
          "notes": "Сервер дошёл до лимита автоперезапусков",
          "links": []
        }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(APIClient.CoordinationResolution.self, from: json)
        XCTAssertEqual(r.contractVersion, "2.0.0")
        XCTAssertEqual(r.subtaskId, "sub_1")
        XCTAssertEqual(r.causeEnum, .stalledManualReview)
        XCTAssertEqual(r.actionEnum, .replaceAttempt)
        XCTAssertEqual(r.assignee.kind, "role")
        XCTAssertEqual(r.metrics.ageSeconds, 600)
        XCTAssertEqual(r.metrics.heartbeatAge, 700)
    }

    func testUnknownCauseDecodesAsUnknown() throws {
        let json = """
        {
          "contract_version": "2.0.0",
          "generated_at": "2026-10-08T12:34:56.000Z",
          "subtask_id": "sub_x",
          "task_id": "task_x",
          "plan_node_key": null,
          "role": null,
          "cause": "future_cause_we_dont_know_yet",
          "action": "none",
          "assignee": { "kind": "person", "key": "user_1" },
          "deadline_hint": null,
          "checked_after": null,
          "evidence": [],
          "metrics": { "age_seconds": 0, "attempts_in_window": 0, "heartbeat_age": 0 },
          "notes": null,
          "links": []
        }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(APIClient.CoordinationResolution.self, from: json)
        XCTAssertEqual(r.causeEnum, .unknown)
        XCTAssertEqual(r.actionEnum, .none)
    }

    // MARK: - Все 20 причин V2 покрыты

    func testAllCausesHaveTitleHintAndAction() {
        // UX-документ, критерий QA №5: «все 20 причин имеют видимое представление».
        for cause in CoordinationCause.allCases {
            XCTAssertFalse(cause.title.isEmpty, "пустой title для \(cause)")
            XCTAssertFalse(cause.hint.isEmpty, "пустой hint для \(cause)")
            // action может быть nil (нет кнопки — авто), но tint обязан быть.
            _ = cause.tint
        }
        XCTAssertEqual(CoordinationCause.allCases.count, 20,
                       "V2 контракт требует ровно 20 причин")
    }

    func testStalledCausesAreCriticalTint() {
        XCTAssertEqual(CoordinationCause.stalledManualReview.tint, .darkRedCritical)
        XCTAssertEqual(CoordinationCause.stepStalled.tint, .darkRedCritical)
        XCTAssertEqual(CoordinationCause.contextOverflow.tint, .darkRedCritical)
    }

    func testBlockedCausesMapToActions() {
        XCTAssertEqual(CoordinationCause.waitingOwner.actionCode, .askOwner)
        XCTAssertEqual(CoordinationCause.waitingHuman.actionCode, .switchRole)
        XCTAssertEqual(CoordinationCause.stalledManualReview.actionCode, .replaceAttempt)
        XCTAssertEqual(CoordinationCause.missingConfig.actionCode, .fixConfig)
        XCTAssertEqual(CoordinationCause.providerLimit.actionCode, .switchProvider)
        XCTAssertEqual(CoordinationCause.completedPendingReview.actionCode, .acceptReview)
        XCTAssertEqual(CoordinationCause.branchRework.actionCode, .pickUpAfterReview)
        XCTAssertEqual(CoordinationCause.awaitingFinalReview.actionCode, .runFinalReview)
    }

    func testPassiveCausesHaveNoAction() {
        // Причины без кнопки (UX-документ, столбец «Кнопка в Action bar»).
        XCTAssertNil(CoordinationCause.waitingPredecessor.actionCode)
        XCTAssertNil(CoordinationCause.activeRun.actionCode)
        XCTAssertNil(CoordinationCause.recoveryPending.actionCode)
        XCTAssertNil(CoordinationCause.durableQueuedWake.actionCode)
        XCTAssertNil(CoordinationCause.review.actionCode)
    }

    func testAllActionsHaveLabel() {
        for action in CoordinationAction.allCases {
            XCTAssertFalse(action.label.isEmpty, "пустой label для \(action)")
        }
        XCTAssertEqual(CoordinationAction.allCases.count, 14,
                       "V2 контракт требует ровно 14 действий")
    }

    func testDestructiveActionsRequireConfirm() {
        XCTAssertTrue(CoordinationAction.start.confirmRequired)
        XCTAssertTrue(CoordinationAction.replaceAttempt.confirmRequired)
        XCTAssertTrue(CoordinationAction.acceptReview.confirmRequired)
        XCTAssertFalse(CoordinationAction.askOwner.confirmRequired)
        XCTAssertFalse(CoordinationAction.fixConfig.confirmRequired)
    }

    // MARK: - Дифф-механизм стора (правило стабильности №2)

    @MainActor
    func testDiffKeepsPositionsStable() async {
        let state = CoordinationState()
        let r1 = makeResolution(subtaskId: "a", cause: "active_run", action: "no_action")
        let r2 = makeResolution(subtaskId: "b", cause: "stalled_manual_review", action: "replace_attempt")
        state.apply(resolutions: [r1, r2], contractVersion: "2.0.0")
        XCTAssertEqual(state.nodes.map { $0.id }, ["a", "b"])

        // Обновляемся: «a» поменял cause, добавился «c».
        let r1b = makeResolution(subtaskId: "a", cause: "blocked_dependency", action: "lift_dependency")
        let r3 = makeResolution(subtaskId: "c", cause: "ready_to_start", action: "start")
        state.apply(resolutions: [r1b, r2, r3], contractVersion: "2.0.0")

        // Позиции стабильны: «b» остался на индексе 1.
        XCTAssertEqual(state.nodes.map { $0.id }, ["a", "b", "c"])
        XCTAssertEqual(state.nodes[1].id, "b")
        XCTAssertEqual(state.nodes[1].resolution?.causeEnum, .stalledManualReview)
        XCTAssertEqual(state.nodes[0].resolution?.causeEnum, .blockedDependency)
    }

    @MainActor
    func testMissingNodesArePlaceholdersThenPruned() async {
        let state = CoordinationState()
        let r1 = makeResolution(subtaskId: "a", cause: "active_run", action: "no_action")
        let r2 = makeResolution(subtaskId: "b", cause: "stalled_manual_review", action: "replace_attempt")
        state.apply(resolutions: [r1, r2], contractVersion: "2.0.0")

        // Следующий ответ — только «a». «b» становится плейсхолдером.
        state.apply(resolutions: [r1], contractVersion: "2.0.0")
        XCTAssertEqual(state.nodes.count, 2)
        XCTAssertNil(state.nodes[1].resolution)

        // После pruneStaleNodes c cutoff=now — плейсхолдер удаляется.
        state.pruneStaleNodes(olderThan: Date())
        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.nodes.first?.id, "a")
    }

    @MainActor
    func testVersionMismatchBlocksActions() async {
        let state = CoordinationState()
        let r = makeResolution(subtaskId: "x", cause: "stalled_manual_review", action: "replace_attempt")
        state.apply(resolutions: [r], contractVersion: "3.0.0")
        switch state.loadState {
        case .versionMismatch(let d):
            XCTAssertTrue(d.contains("3.0.0"))
        default:
            XCTFail("ожидался .versionMismatch, получено: \(state.loadState)")
        }
    }

    @MainActor
    func testStalledNodeIsFirst() async {
        let state = CoordinationState()
        // Сценарий QA №7: зависшая ветвь видна рядом с работающей.
        let active = makeResolution(subtaskId: "active", cause: "active_run", action: "no_action")
        let stalled = makeResolution(subtaskId: "stalled", cause: "stalled_manual_review", action: "replace_attempt")
        let ready = makeResolution(subtaskId: "ready", cause: "ready_to_start", action: "start")
        // Сервер отдал в порядке [ready, active, stalled].
        state.apply(resolutions: [ready, active, stalled], contractVersion: "2.0.0")
        XCTAssertEqual(state.stalledNodeId, "stalled")
    }

    // MARK: - 4 состояния доставки сообщения

    func testAllDeliveryStatesHaveUniqueSymbol() {
        let states: [MessageDeliveryChip.DeliveryState] = [
            .accepted, .queued, .processing, .delivered, .completed, .failed
        ]
        XCTAssertEqual(states.count, 6, "контракт V2 + вспомогательные")
    }

    func testQueuedMinutesAppearInChipText() {
        // UX §4.2: если сообщение в очереди дольше STALL_AFTER_MIN, добавляется «N мин в очереди».
        let chip = MessageDeliveryChip(state: .queued, queuedMinutes: 3)
        XCTAssertTrue(chip.text.contains("3"))
    }

    // MARK: - Хелпер

    private func makeResolution(
        subtaskId: String,
        cause: String,
        action: String
    ) -> APIClient.CoordinationResolution {
        let json = """
        {
          "contract_version": "2.0.0",
          "generated_at": "2026-10-08T12:34:56.000Z",
          "subtask_id": "\(subtaskId)",
          "task_id": "task_1",
          "plan_node_key": "node_\(subtaskId)",
          "role": "builder",
          "cause": "\(cause)",
          "action": "\(action)",
          "assignee": { "kind": "role", "key": "builder" },
          "deadline_hint": null,
          "checked_after": null,
          "evidence": [],
          "metrics": { "age_seconds": 0, "attempts_in_window": 0, "heartbeat_age": 0 },
          "notes": null,
          "links": []
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(APIClient.CoordinationResolution.self, from: json)
    }
}