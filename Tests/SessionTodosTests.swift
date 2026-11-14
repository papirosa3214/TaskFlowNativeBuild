import XCTest

/// Список дел агента Pi в сессии: готовый ответ сервера → полоса чек-листа
/// (`ChatWorkPlanRows`). Здесь только разбор и отбор, вид компонента не
/// проверяется — его оценивает владелец.
final class SessionTodosTests: XCTestCase {
    private func decode(_ json: String) throws -> SessionTodosResponse {
        try JSONDecoder().decode(SessionTodosResponse.self, from: Data(json.utf8))
    }

    private func todos(_ json: String) throws -> SessionTodos {
        let response = try decode(json)
        return try XCTUnwrap(response.todos)
    }

    /// Пункты, статусы и текущий пункт — как их прислал сервер; кружки рисует
    /// общий компонент по состоянию пункта.
    func testPlanKeepsServerStatesAndCounts() throws {
        let todos = try todos("""
        {"todos":{"sessionId":"s1","available":true,"entryId":"e9","updatedAt":"2026-11-14T10:00:00.000Z",
        "nextId":4,"tasks":[
        {"id":1,"subject":"Прочитать AGENT-CYCLE","status":"completed"},
        {"id":2,"subject":"Найти чек-лист","status":"in_progress","activeForm":"ищу компонент"},
        {"id":3,"subject":"Собрать список","status":"pending","blockedBy":[2]}],
        "counts":{"pending":1,"in_progress":1,"completed":1}}}
        """)
        let plan = try XCTUnwrap(todos.plan(sessionID: "s1"))

        XCTAssertEqual(plan.chatID, "s1")
        XCTAssertEqual(plan.roleID, SessionTodos.planID)
        XCTAssertEqual(plan.items.map(\.state), [.done, .inProgress, .pending])
        XCTAssertEqual(plan.items.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(plan.doneCount, 1)
        XCTAssertEqual(plan.current?.id, "2")
        XCTAssertEqual(plan.currentItemID, "2")
        XCTAssertEqual(plan.status, .active)
    }

    /// У идущей задачи агент ведёт форму действия — показываем её, как в Pi;
    /// остальные пункты остаются своим текстом.
    func testRunningTaskShowsActiveForm() throws {
        let todos = try todos("""
        {"todos":{"sessionId":"s1","available":true,"entryId":"e1","updatedAt":"2026-11-14T10:00:00.000Z",
        "nextId":3,"tasks":[
        {"id":1,"subject":"Собрать список","status":"in_progress","activeForm":"собираю список"},
        {"id":2,"subject":"Проверить","status":"pending"}],"counts":{}}}
        """)
        let plan = try XCTUnwrap(todos.plan(sessionID: "s1"))
        XCTAssertEqual(plan.items.first?.title, "собираю список")
        XCTAssertEqual(plan.items.last?.title, "Проверить")
    }

    /// Агент ещё не вёл список или он пуст — полосы нет, пустой строки тоже.
    func testMissingOrEmptyListHasNoStrip() throws {
        XCTAssertNil(try decode(#"{}"#).todos)
        XCTAssertNil(try decode(#"{"todos":null}"#).todos)
        let unavailable = try todos("""
        {"todos":{"sessionId":"s1","available":false,"tasks":[],"counts":{}}}
        """)
        XCTAssertNil(unavailable.plan(sessionID: "s1"))

        let empty = try todos("""
        {"todos":{"sessionId":"s1","available":true,"entryId":"e1","updatedAt":"2026-11-14T10:00:00.000Z",
        "nextId":1,"tasks":[],"counts":{}}}
        """)
        XCTAssertNil(empty.plan(sessionID: "s1"))
    }

    /// Незнакомый статус не должен выбрасывать весь список и не рисуется
    /// закрытым кружком — сервер вправе добавить своё состояние.
    func testUnknownStatusFallsBackToPending() throws {
        let todos = try todos("""
        {"todos":{"sessionId":"s1","available":true,"entryId":"e1","updatedAt":"2026-11-14T10:00:00.000Z",
        "nextId":3,"tasks":[
        {"id":1,"subject":"Старое","status":"archived"},
        {"id":2,"subject":"Готово","status":"completed"}],"counts":{}}}
        """)
        let plan = try XCTUnwrap(todos.plan(sessionID: "s1"))
        XCTAssertEqual(plan.items.map(\.state), [.pending, .done])
        XCTAssertEqual(plan.doneCount, 1)
    }

    /// Поздний ответ на старый запрос и ответ чужой сессии не ложатся поверх
    /// того, что уже на экране.
    func testStaleAndForeignListsAreRejected() throws {
        let current = try todos("""
        {"todos":{"sessionId":"s1","available":true,"entryId":"e2","updatedAt":"2026-11-14T10:00:02.000Z",
        "nextId":2,"tasks":[{"id":1,"subject":"Новое","status":"pending"}],"counts":{}}}
        """)
        let older = try todos("""
        {"todos":{"sessionId":"s1","available":true,"entryId":"e1","updatedAt":"2026-11-14T10:00:01.000Z",
        "nextId":2,"tasks":[{"id":1,"subject":"Старое","status":"pending"}],"counts":{}}}
        """)
        let foreign = try todos("""
        {"todos":{"sessionId":"s2","available":true,"entryId":"e3","updatedAt":"2026-11-14T10:00:03.000Z",
        "nextId":2,"tasks":[{"id":1,"subject":"Чужая сессия","status":"pending"}],"counts":{}}}
        """)

        XCTAssertFalse(SessionTodos.isNewer(older, than: current))
        XCTAssertFalse(SessionTodos.isNewer(foreign, than: current))
        XCTAssertTrue(SessionTodos.isNewer(current, than: older))
        XCTAssertTrue(SessionTodos.isNewer(current, than: nil))
    }
}
