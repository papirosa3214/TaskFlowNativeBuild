import XCTest
@testable import TaskFlow

/// События реалтайма не должны перезагружать списки ролей и работ на каждое
/// событие: во время работы агентов события идут пачками, и каждый экран
/// уходил в сеть со своим запросом. Инвалидация схлопывается в окно 0.5 с —
/// свежесть экрана та же, а запросов в разы меньше.
@MainActor
final class RealtimeInvalidationCoalescingTests: XCTestCase {

    func testПачкаСобытийЗадачиДаётОднуИнвалидацию() async throws {
        let client = RealtimeClient()
        let task = try JSONDecoder().decode(ApiTask.self, from: Data(#"{"id":"task-1","title":"Задача","priority":3,"status":"active"}"#.utf8))

        for _ in 0..<5 {
            client.record(.taskUpdated(task))
        }

        // Пока окно не вышло — инвалидация ещё не выставлена.
        XCTAssertEqual(client.rolesRevision, 0, "Инвалидация выставилась сразу, а не по окну")
        XCTAssertEqual(client.jobsRevision, 0)

        try await ContinuousClock().sleep(for: .milliseconds(700))

        XCTAssertEqual(client.rolesRevision, 1, "Пять событий должны дать одну инвалидацию")
        XCTAssertEqual(client.jobsRevision, 1)
    }

    func testИзменениеРолейОстаётсяМгновенным() async throws {
        let client = RealtimeClient()
        client.record(.rolesChanged)
        XCTAssertEqual(client.rolesRevision, 1, "Изменение состава ролей ждать не должно")
    }

    func testРевизияЗадачиРастётСразу() async throws {
        let client = RealtimeClient()
        let task = try JSONDecoder().decode(ApiTask.self, from: Data(#"{"id":"task-1","title":"Задача","priority":3,"status":"active"}"#.utf8))
        client.record(.taskUpdated(task))
        XCTAssertEqual(client.taskRevisions["task-1"], 1, "Карточка задачи обновляется без задержки")
    }
}
