import Foundation
import XCTest
@testable import TaskFlow

/// Правила применения ответа сервера к локальному кэшу задач
/// (LOCK-CACHE-SYNC-BATCH-20261102).
///
/// Проверяется то, что ломается ТИХО и выглядит как «жёсткий рассинхрон»
/// между сервером и телефоном (заметка «Кэш и синхронизация в мобильных
/// клиентах», раздел 4.2):
/// - отпечаток (ETag) без тела: сервер отвечает 304, телефон остаётся с
///   пустым или старым списком навсегда;
/// - курсор, сдвинутый раньше применения дельты: потерянное изменение не
///   придёт больше никогда.
///
/// Файл правил — `Sources/Core/Store/TaskSyncCachePolicy.swift`: в нём нет ни
/// БД, ни сети, поэтому те же проверки гоняются на macOS без симулятора
/// (`Tools/test_task_sync_cache.py`).
final class TaskSyncCachePolicyTests: XCTestCase {
    // MARK: - Отпечаток без тела

    func testETagIsNotSentWhenLocalBodyIsMissing() {
        // Тела нет — условие посылать нельзя: сервер ответит 304 «не
        // менялось», а показать будет нечего.
        XCTAssertNil(TaskSyncCachePolicy.etagToSend(localHasBody: false, etag: "W/\"abc\""))
    }

    func testETagIsSentWhenLocalBodyExists() {
        XCTAssertEqual(
            TaskSyncCachePolicy.etagToSend(localHasBody: true, etag: "W/\"abc\""),
            "W/\"abc\""
        )
    }

    func testNoETagMeansNoCondition() {
        XCTAssertNil(TaskSyncCachePolicy.etagToSend(localHasBody: true, etag: nil))
    }

    // MARK: - 304 без тела

    func testNotModifiedWithoutBodyRequiresRetry() {
        XCTAssertTrue(
            TaskSyncCachePolicy.needsBodyRetry(notModified: true, localHasBody: false)
        )
    }

    func testNotModifiedWithBodyNeedsNoRetry() {
        XCTAssertFalse(
            TaskSyncCachePolicy.needsBodyRetry(notModified: true, localHasBody: true)
        )
    }

    func testBodyReceivedNeedsNoRetry() {
        XCTAssertFalse(
            TaskSyncCachePolicy.needsBodyRetry(notModified: false, localHasBody: false)
        )
    }

    // MARK: - Курсор дельты

    func testCursorAdvancesOnlyWhenWholeDeltaApplied() {
        // Часть карточек не пришла — курсор двигать нельзя: сервер больше
        // их не пришлёт.
        XCTAssertFalse(
            TaskSyncCachePolicy.canAdvanceCursor(
                appliedIds: ["a"],
                requestedIds: ["a", "b"]
            )
        )
    }

    func testCursorAdvancesWhenAllApplied() {
        XCTAssertTrue(
            TaskSyncCachePolicy.canAdvanceCursor(
                appliedIds: ["a", "b"],
                requestedIds: ["a", "b"]
            )
        )
    }

    func testCursorAdvancesForEmptyDelta() {
        XCTAssertTrue(
            TaskSyncCachePolicy.canAdvanceCursor(appliedIds: [], requestedIds: [])
        )
    }

    func testServerAnsweredThatCardIsGoneCountsAsApplied() {
        // «Такой карточки больше нет» — тоже ответ сервера, догонять нечего.
        XCTAssertTrue(
            TaskSyncCachePolicy.canAdvanceCursor(
                appliedIds: ["a", "b"],
                requestedIds: ["a", "b"]
            )
        )
    }

    // MARK: - Батч

    func testBatchRequestIdsDropDuplicates() {
        XCTAssertEqual(
            TaskSyncCachePolicy.batchRequestIds(changedIds: ["a", "b", "a"]),
            ["a", "b"]
        )
    }

    func testBatchRequestIdsRespectLimit() {
        let ids = TaskSyncCachePolicy.batchRequestIds(changedIds: ["a", "b", "c"], limit: 2)
        XCTAssertEqual(ids, ["a", "b"])
    }

    func testBatchRequestIdsSkipEmpty() {
        XCTAssertEqual(TaskSyncCachePolicy.batchRequestIds(changedIds: ["", "a"]), ["a"])
    }
}
