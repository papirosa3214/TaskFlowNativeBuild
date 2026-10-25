import XCTest
@testable import TaskFlow

/// Серверные состояния пункта чатового чек-листа и различие «сообщение
/// сохранено / передано исполнителю» (карточка b504958a, контракт §3.3 и §10).
/// Клиент ничего не вычисляет сам: он рисует то, что посчитал сервер.
final class ChatWorkPlanServerStateTests: XCTestCase {
    private func plan(_ json: String) throws -> ChatWorkPlan {
        let response = try JSONDecoder().decode(ChatWorkPlansResponse.self, from: Data(json.utf8))
        return try XCTUnwrap(response.plans.first)
    }

    /// Поля ровно те, что отдаёт сервер после коммита d9ab378a.
    private let stoppedPlanJSON = #"""
    {"plans":[{"chat_id":"c1","role_id":"role_builder","revision":4,"status":"stopped",
      "stop_reason":"owner_stop","stopped_at":"2026-10-25T04:00:00Z","current_item_id":null,
      "updated_at":"2026-10-25T04:00:00Z","items":[
        {"id":"read","title":"Прочитать контракт","state":"done","result":"Контракт зафиксирован."},
        {"id":"impl","title":"Реализовать конвейер","state":"blocked","block_reason":"Нужен ответ владельца"},
        {"id":"ui","title":"Показать состояния","state":"stopped"},
        {"id":"qa","title":"Проверить","state":"pending"}]}]}
    """#

    private let activePlanJSON = #"""
    {"plans":[{"chat_id":"c1","role_id":"role_builder","revision":2,"status":"active",
      "stop_reason":null,"stopped_at":null,"current_item_id":"impl","updated_at":"2026-10-25T04:00:00Z",
      "items":[
        {"id":"read","title":"Прочитать контракт","state":"done","result":"Контракт зафиксирован."},
        {"id":"impl","title":"Реализовать конвейер","state":"in_progress"},
        {"id":"qa","title":"Проверить","state":"pending"}]}]}
    """#

    func testItemStatesComeFromServer() throws {
        let plan = try plan(stoppedPlanJSON)
        XCTAssertEqual(plan.status, .stopped)
        XCTAssertEqual(plan.items.map(\.state), [.done, .blocked, .stopped, .pending])
        XCTAssertEqual(plan.items.map(\.state.label), ["Выполнено", "Заблокировано", "Остановлено", "Ожидает"])
        XCTAssertEqual(plan.items.map(\.state.symbol), ["checkmark.square.fill", "exclamationmark.square.fill", "stop.square.fill", "square"])
        XCTAssertNil(plan.current)
        XCTAssertEqual(plan.doneCount, 1)
    }

    func testStoppedPlanSummaryExplainsWhoStopped() throws {
        let plan = try plan(stoppedPlanJSON)
        XCTAssertEqual(plan.summary(roleName: "Разработчик"),
                       "План остановлен · Разработчик · 1 из 4 · остановил владелец")
    }

    func testBlockedItemShowsServerReason() throws {
        let plan = try plan(stoppedPlanJSON)
        XCTAssertEqual(plan.items[1].statusNote, "Ждёт: Нужен ответ владельца")
        XCTAssertEqual(plan.items[2].statusNote, "Остановлено")
        XCTAssertNil(plan.items[3].statusNote)
    }

    func testDoneItemShowsAcceptedResult() throws {
        let plan = try plan(stoppedPlanJSON)
        XCTAssertEqual(plan.items[0].statusNote, "Результат: Контракт зафиксирован.")
    }

    func testActivePlanSummaryNamesCurrentItem() throws {
        let plan = try plan(activePlanJSON)
        XCTAssertEqual(plan.status, .active)
        XCTAssertEqual(plan.current?.id, "impl")
        XCTAssertEqual(plan.summary(roleName: "Разработчик"),
                       "План · Разработчик · 1 из 3 · сейчас: Реализовать конвейер")
    }

    func testPlanWithoutServerFieldsStillDecodes() throws {
        let legacy = #"{"plans":[{"chat_id":"c1","role_id":"role_builder","revision":1,"updated_at":"x","items":[{"id":"a","title":"Шаг","state":"in_progress"}]}]}"#
        let plan = try plan(legacy)
        XCTAssertEqual(plan.status, .active)
        XCTAssertNil(plan.stopReason)
        XCTAssertEqual(plan.current?.id, "a")
    }

    private func message(_ json: String) throws -> RoleChatMessage {
        try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
    }

    private func roleMessage(delivery: String?) throws -> RoleChatMessage {
        let state = delivery.map { ",\"queue_delivery_state\":\"\($0)\"" } ?? ""
        let json = "{\"id\":\"m1\",\"text\":\"Готово\",\"chat_id\":\"c1\",\"from_user_id\":\"role_builder\",\"is_session_marker\":false\(state)}"
        return try message(json)
    }

    func testMessageDeliveryStatesAreDistinct() throws {
        XCTAssertEqual(try roleMessage(delivery: "saved").queueDeliveryState, .saved)
        XCTAssertEqual(try roleMessage(delivery: "queued").queueDeliveryState, .queued)
        XCTAssertEqual(try roleMessage(delivery: "accepted").queueDeliveryState, .accepted)
        XCTAssertEqual(try roleMessage(delivery: "stale").queueDeliveryState, .stale)
        XCTAssertNil(try roleMessage(delivery: nil).queueDeliveryState)
    }

    func testDeliveryLabelsTellSavedFromDelivered() throws {
        XCTAssertEqual(ChatMessageDeliveryState.saved.label, "Сохранено")
        XCTAssertEqual(ChatMessageDeliveryState.queued.label, "В очереди")
        XCTAssertEqual(ChatMessageDeliveryState.accepted.label, "Передано исполнителю")
        XCTAssertEqual(ChatMessageDeliveryState.stale.label, "Не передано")
        XCTAssertTrue(ChatMessageDeliveryState.stale.isProblem)
        XCTAssertFalse(ChatMessageDeliveryState.accepted.isProblem)
    }
}
