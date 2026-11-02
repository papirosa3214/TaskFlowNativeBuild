import Foundation
import XCTest
@testable import TaskFlow

/// Правила догона сущностей вне карточек (LOCK-SYNC-ENTITY-DELTA-20261102).
///
/// Проверяется то, что ломается ТИХО: правка рутины или заметки на сервере
/// не доезжает до телефона после разрыва связи, и телефон этого не замечает
/// (заметка «Техническое решение и риски», карточка 2980844e).
///
/// Файл правил — `Sources/Core/Store/EntitySyncPolicy.swift`: в нём нет ни БД,
/// ни сети, поэтому те же проверки гоняются на macOS без симулятора
/// (`Tools/test_entity_sync.py`).
final class EntitySyncPolicyTests: XCTestCase {
    // MARK: - Что перечитывать

    func testChangedProjectTriggersProjectReload() {
        var input = EntitySyncPlanInput()
        input.changed[.projects] = ["p1"]
        let plan = EntitySyncPolicy.plan(for: input)
        XCTAssertTrue(plan.reloadProjects)
        XCTAssertFalse(plan.reloadLabels)
        XCTAssertFalse(plan.reloadRoutines)
    }

    func testRemovedRoutineTriggersRoutinesReload() {
        // Удаление едет тем же потоком, что и правка: клиент узнаёт о нём
        // из removed_ids, а не догадывается по отсутствию рутины в списке.
        var input = EntitySyncPlanInput()
        input.removed[.schedules] = ["s1"]
        let plan = EntitySyncPolicy.plan(for: input)
        XCTAssertTrue(plan.reloadRoutines)
    }

    func testChangedNoteTriggersNotesReload() {
        var input = EntitySyncPlanInput()
        input.changed[.notes] = ["n1"]
        XCTAssertTrue(EntitySyncPolicy.plan(for: input).reloadNotes)
    }

    func testChangedLabelTriggersLabelReload() {
        var input = EntitySyncPlanInput()
        input.changed[.labels] = ["l1"]
        XCTAssertTrue(EntitySyncPolicy.plan(for: input).reloadLabels)
    }

    func testFullDeltaReloadsEverything() {
        // Журнал не покрыл нужный момент — читаем всё, иначе останется хвост
        // старых данных.
        let plan = EntitySyncPolicy.plan(for: EntitySyncPlanInput(full: true))
        XCTAssertTrue(plan.reloadProjects)
        XCTAssertTrue(plan.reloadLabels)
        XCTAssertTrue(plan.reloadNotes)
        XCTAssertTrue(plan.reloadRoutines)
    }

    func testEmptyDeltaNeedsNothing() {
        let plan = EntitySyncPolicy.plan(for: EntitySyncPlanInput())
        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(EntitySyncPolicy.steps(for: plan).isEmpty)
    }

    // MARK: - Разбор ответа сервера

    func testDeltaFromServerIsParsedByType() {
        let json = """
        {
          "server_time": "s:42",
          "cursor": "s:42",
          "full": false,
          "entities": {
            "projects": { "changed_ids": ["p1"], "removed_ids": [] },
            "schedules": { "changed_ids": [], "removed_ids": ["s1"] }
          }
        }
        """.data(using: .utf8)!
        let delta = try! JSONDecoder().decode(EntitySyncDelta.self, from: json)
        let plan = EntitySyncPolicy.plan(for: delta)
        XCTAssertTrue(plan.reloadProjects)
        XCTAssertFalse(plan.reloadLabels)
        XCTAssertTrue(plan.reloadRoutines)
        XCTAssertFalse(plan.reloadNotes)
    }

    func testMissingBucketIsEmpty() {
        // Старый сервер может не знать какой-то тип — дефолт пустой, а не
        // падение.
        let json = """
        { "server_time": "s:1", "cursor": "s:1", "full": false, "entities": {} }
        """.data(using: .utf8)!
        let delta = try! JSONDecoder().decode(EntitySyncDelta.self, from: json)
        XCTAssertTrue(delta.bucket("projects").changedIds.isEmpty)
        XCTAssertTrue(EntitySyncPolicy.plan(for: delta).isEmpty)
    }

    // MARK: - Курсор

    func testCursorDoesNotAdvanceWhenSomeStepFailed() {
        // Курсор означает «до этого места я догнал». Если часть дельты не
        // применилась, курсор двигать нельзя — иначе изменение потеряется
        // навсегда.
        XCTAssertFalse(EntitySyncPolicy.canAdvanceCursor(failedSteps: [.projects]))
        XCTAssertFalse(EntitySyncPolicy.canAdvanceCursor(failedSteps: [.projects, .notes]))
    }

    func testCursorAdvancesWhenAllStepsSucceeded() {
        XCTAssertTrue(EntitySyncPolicy.canAdvanceCursor(failedSteps: []))
    }
}
