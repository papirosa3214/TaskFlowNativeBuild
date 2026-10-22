import XCTest
@testable import TaskFlow

/// Карточка 6dee5bc3: поломка, чью карточку починки отправили в архив,
/// обязана исчезнуть из «Состояния системы» — из строк сводки и из ленты
/// уведомлений, — и не возвращаться, пока та же поломка не возникнет снова.
///
/// Сторона сервера отдаёт закрытые поломки отдельным списком (`closed` в
/// `GET /api/system-state`): архивные поломки из `incidents` исключены, и
/// без этого списка клиент не понимает, что строку проверки пора убрать.
final class SystemSummaryClosedIncidentTests: XCTestCase {

    // Живой ответ `GET /api/system-state`: одна живая поломка и одна
    // закрытая — с тем же ключом (ключ поломки один на причину).
    private let stateJSON = """
    {"from":"2026-10-21T00:00:00.000Z",
     "counts":{"total":1,"open":1,"fixed":0,"in_work":0},
     "incidents":[{"id":"live-1","key":"automerge-dirty","title":"Автослияние стоит","fixed":false,
                   "state":null,"assignee_name":null,"work_seconds":0,"workers":[]}],
     "closed":[{"id":"closed-1","key":"automerge-dirty"}],
     "workers":[]}
    """

    // Старый сервер: поля `closed` ещё нет — это не поломка.
    private let oldStateJSON = """
    {"from":"2026-10-21T00:00:00.000Z",
     "counts":{"total":0,"open":0,"fixed":0,"in_work":0},
     "incidents":[],"workers":[]}
    """

    private func decode(_ json: String) throws -> SystemState {
        try JSONDecoder().decode(SystemState.self, from: Data(json.utf8))
    }

    private func liveIncident() -> SystemState.Incident {
        SystemState.Incident(id: "live-1", key: "automerge-dirty", title: "Автослияние стоит",
                             fixed: false, state: nil, assignee_name: nil,
                             work_seconds: 0, workers: [])
    }

    private func closedIncident() -> SystemState.Closed {
        SystemState.Closed(id: "closed-1", key: "automerge-dirty")
    }

    // MARK: - Разбор ответа сервера

    func test_closedIncidentsAreDecoded() throws {
        let state = try decode(stateJSON)
        XCTAssertEqual(state.closed.count, 1)
        XCTAssertEqual(state.closed.first?.id, "closed-1")
        XCTAssertEqual(state.closed.first?.key, "automerge-dirty")
    }

    func test_serverWithoutClosedFieldIsNotAnError() throws {
        let state = try decode(oldStateJSON)
        XCTAssertTrue(state.closed.isEmpty)
    }

    // MARK: - Строки сводки

    /// Строка проверки, привязанная к закрытой поломке по ключу, не рисуется.
    func test_checkOfClosedIncidentIsNotDrawn() {
        let check = ServiceTicketCheck(name: "Автослияние стоит", area: "Сервер", status: "error",
                                       message: "main грязный дольше 6 часов",
                                       incidentKey: "automerge-dirty")
        let rows = SystemSummaryItem.compose(checks: [check], incidents: [],
                                             closedIncidents: [closedIncident()])
        XCTAssertTrue(rows.isEmpty)
    }

    /// Та же строка, привязанная к закрытой поломке по id карточки.
    func test_checkLinkedToClosedIncidentByCardIDIsNotDrawn() {
        let check = ServiceTicketCheck(name: "Автослияние стоит", area: "Сервер", status: "error",
                                       message: "main грязный дольше 6 часов",
                                       diagnosticTaskIDs: ["closed-1"])
        let rows = SystemSummaryItem.compose(checks: [check], incidents: [],
                                             closedIncidents: [closedIncident()])
        XCTAssertTrue(rows.isEmpty)
    }

    /// Поломка возникла снова: у неё новая карточка, строка возвращается.
    func test_liveIncidentWinsOverClosedOne() {
        let check = ServiceTicketCheck(name: "Автослияние стоит", area: "Сервер", status: "error",
                                       message: "main грязный дольше 6 часов",
                                       incidentKey: "automerge-dirty")
        let rows = SystemSummaryItem.compose(checks: [check], incidents: [liveIncident()],
                                             closedIncidents: [closedIncident()])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .broken)
        XCTAssertEqual(rows.first?.taskID, "live-1")
    }

    /// Чужая проверка без связи с поломкой остаётся на месте.
    func test_unrelatedCheckStaysVisible() {
        let check = ServiceTicketCheck(name: "Проверка сервиса", area: "Сервер", status: "ok",
                                       message: "Работает")
        let rows = SystemSummaryItem.compose(checks: [check], incidents: [],
                                             closedIncidents: [closedIncident()])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .normal)
    }

    /// Без списка закрытых поломок поведение прежнее: строка на месте.
    func test_withoutClosedListNothingIsHidden() {
        let check = ServiceTicketCheck(name: "Автослияние стоит", area: "Сервер", status: "error",
                                       message: "main грязный дольше 6 часов",
                                       incidentKey: "automerge-dirty")
        let rows = SystemSummaryItem.compose(checks: [check], incidents: [])
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - Реакция на архив

    /// Карточка ушла в архив — экран «Состояние системы» должен узнать и
    /// перечитать сводку. Событие приходит по WS как `task:archived`.
    @MainActor
    func test_archivedTaskBumpsRevision() throws {
        let store = TaskStore(apiClient: APIClient())
        let archived = #"{"id":"archive-test","title":"Поломка","status":"active","archived_at":"2026-10-21 01:00:00","labels":[],"subtasks":[]}"#
        let event = try XCTUnwrap(RealtimeEvent.parse(Data("{\"type\":\"task:archived\",\"task\":\(archived)}".utf8)))
        XCTAssertEqual(store.archivedRevision, 0)
        store.apply(event)
        XCTAssertEqual(store.archivedRevision, 1)
    }
}
