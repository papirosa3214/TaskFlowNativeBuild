import Foundation
import XCTest
@testable import TaskFlow

/// Строка очереди автослияния в карточке (сервер: `GET /api/merges/queue`).
/// Проверяем разбор ответа и подписи состояний — от них зависит, что
/// владелец видит в «Итоге» и когда появляется кнопка отката.
final class TaskMergeStateTests: XCTestCase {
    func testРазбираетФормуОтветаСервера() throws {
        let json = """
        {
          "mode": "on",
          "test_timeout_min": 20,
          "live_repo": "/home/maksim/Проекты/New-Todoist",
          "rows": [
            {
              "task_id": "t-1",
              "trigger": "integration_step",
              "state": "test_failed",
              "main_sha_before": "71e3ee88",
              "result_sha": "3bbf253a",
              "error": "новые падения после слияния: test/roles.test.ts",
              "attempts": 0,
              "created_at": "2026-10-19 02:43:41",
              "updated_at": "2026-10-19 02:43:41",
              "finished_at": null
            }
          ]
        }
        """
        let queue = try JSONDecoder().decode(ApiMergeQueue.self, from: Data(json.utf8))
        XCTAssertEqual(queue.mode, "on")
        XCTAssertEqual(queue.rows.count, 1)
        let row = try XCTUnwrap(queue.rows.first)
        XCTAssertEqual(row.taskID, "t-1")
        XCTAssertEqual(row.state, .testFailed)
        XCTAssertEqual(row.shortSHA, "3bbf253a")
        XCTAssertEqual(queue.row(forTask: "t-1")?.taskID, "t-1")
        XCTAssertNil(queue.row(forTask: "другая"))
    }

    func testПодписиСостоянийЧитаютсяПоЧеловечески() {
        XCTAssertEqual(ApiMergeState.queued.title, "В очереди на слияние")
        XCTAssertEqual(ApiMergeState.merged.title, "Влито в основную ветку")
        XCTAssertEqual(ApiMergeState.conflict.title, "Конфликт — ждёт интегратора")
        XCTAssertEqual(ApiMergeState.testFailed.title, "Тесты красные — ждёт интегратора")
        XCTAssertEqual(ApiMergeState.blockedDirtyMain.title, "Ждёт чистого main")
        XCTAssertEqual(ApiMergeState.dryRun.title, "Проверено, main не тронут")
        XCTAssertEqual(ApiMergeState.nothingToMerge.title, "Сливать нечего")
        XCTAssertEqual(ApiMergeState.missingBranch.title, "Ветка роли исчезла")
        XCTAssertEqual(ApiMergeState.running.title, "Сливается")
        XCTAssertEqual(ApiMergeState.dirtyWorktree.title, "В копии есть незакоммиченное")
        // Неизвестное состояние не должно ломать интерфейс машинным кодом.
        XCTAssertEqual(ApiMergeState(rawValue: "что-то новое").title, "что-то новое")
        XCTAssertEqual(ApiMergeState(rawValue: "что-то новое"), .unknown("что-то новое"))
    }

    func testОткатПредлагаетсяТолькоПослеНастоящегоСлияния() {
        XCTAssertTrue(ApiMergeState.merged.canRollBack)
        let безОтката: [ApiMergeState] = [.queued, .running, .dryRun, .conflict, .testFailed,
                                          .blockedDirtyMain, .nothingToMerge, .missingBranch, .dirtyWorktree]
        for state in безОтката {
            XCTAssertFalse(state.canRollBack, "откат лишний для состояния \(state.rawValue)")
        }
    }
}
