import Foundation
import XCTest
@testable import TaskFlow

/// Наводящая строка карточки «Входящих» (LOCK-ATTENTION-CARD-CONTEXT-20261029).
///
/// Сервер отдаёт в каждой задаче строки `hint` — что делать с задачей, не
/// открывая её карточку. Старый сервер этого поля не отдаёт: тогда строки на
/// карточке просто нет, и клиент ломаться не должен.
final class AttentionCardContextTests: XCTestCase {
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
}
