import Foundation
import XCTest
@testable import TaskFlow

/// Локальная база: запись, чтение и правила слияния (LOCK-LOCAL-DB-SYNC-20261031).
///
/// Проверяется ровно то, что ломается тихо: забытый upsert, потерянный
/// курсор, молчаливое удаление истории.
///
/// Фикстуры — по реальному контракту моделей: `RoleChat` требует
/// `created_by`, `ApiTask` — `title` и `status`. База хранит сырой JSON
/// сервера и читает его настоящей моделью, поэтому запись без обязательного
/// поля отбрасывается при чтении.
final class LocalDbSyncTests: XCTestCase {
    private let store = LocalStore.shared

    /// База в тестах — общая на приложение, поэтому каждый тест чистит её
    /// перед собой и после: иначе тесты влияют друг на друга.
    override func setUp() {
        super.setUp()
        try? store.clearAll()
    }

    override func tearDown() {
        try? store.clearAll()
        super.tearDown()
    }

    // MARK: - Чаты

    func testChatsSurviveRoundTripThroughTheDatabase() throws {
        let payload = Data(#"{"chats":[{"id":"c1","title":"Комната","kind":"group","created_by":"u","members":[],"unread_count":2,"room_kind":"dm","updated_at":"2026-10-31 10:00:00"}]}"#.utf8)
        try store.upsertChats(payload)

        let chats = try store.chats()
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats.first?.id, "c1")
        XCTAssertEqual(chats.first?.title, "Комната")
        XCTAssertEqual(chats.first?.unreadCount, 2)
        XCTAssertEqual(chats.first?.roomKind, "dm")
    }

    func testChatUpsertReplacesTheSameIdWithoutDeletingOthers() throws {
        try store.upsertChats(Data(#"{"chats":[{"id":"c1","title":"Старое","kind":"group","created_by":"u","members":[]},{"id":"c2","title":"Второе","kind":"group","created_by":"u","members":[]}]}"#.utf8))
        try store.upsertChats(Data(#"{"chats":[{"id":"c1","title":"Новое","kind":"group","created_by":"u","members":[]}]}"#.utf8))

        let chats = try store.chats()
        XCTAssertEqual(chats.count, 2, "второй чат не должен исчезнуть при обновлении первого")
        XCTAssertEqual(chats.first(where: { $0.id == "c1" })?.title, "Новое")
    }

    func testClosedChatIsHiddenUnlessExplicitlyAsked() throws {
        try store.upsertChats(Data(#"{"chats":[{"id":"open","title":"Открытая","kind":"group","created_by":"u","members":[]},{"id":"closed","title":"Закрытая","kind":"group","created_by":"u","members":[],"closed_at":"2026-10-31 11:00:00"}]}"#.utf8))

        XCTAssertEqual(try store.chats().map(\.id).sorted(), ["open"])
        XCTAssertEqual(try store.chats(includeClosed: true).count, 2)
    }

    /// «Вернуть из архива» работает пока только на сервере, если локальный
    /// UPDATE обращается к несуществующему столбцу: ошибка глотается `try?`,
    /// и архивный чат остаётся скрытым до полного ответа сервера.
    func testRestoredChatIsVisibleInTheListAgain() throws {
        try store.upsertChats(Data(#"{"chats":[{"id":"closed","title":"Архивная","kind":"group","created_by":"u","members":[],"closed_at":"2026-10-31 11:00:00"}]}"#.utf8))

        XCTAssertTrue(try store.chats().isEmpty)

        try store.showChat(id: "closed")

        XCTAssertEqual(try store.chats().map(\.id), ["closed"])
        XCTAssertEqual(try store.chats(includeClosed: true).count, 1)
    }

    // MARK: - Сообщения

    func testMessagesAreOrderedBySequence() throws {
        let payload = Data(#"{"messages":[{"id":"m2","text":"Второе","sequence":2,"is_session_marker":false},{"id":"m1","text":"Первое","sequence":1,"is_session_marker":false}]}"#.utf8)
        try store.upsertMessages(chatID: "c1", payload: payload)

        let messages = try store.messages(chatID: "c1")
        XCTAssertEqual(messages.map(\.id), ["m1", "m2"])
    }

    func testCursorIsTheNewestMessageNumber() throws {
        try store.upsertMessages(chatID: "c1", payload: Data(#"{"messages":[{"id":"m1","text":"Первое","sequence":7,"is_session_marker":false},{"id":"m2","text":"Второе","sequence":9,"is_session_marker":false}]}"#.utf8))

        XCTAssertEqual(try store.maxSequence(chatID: "c1"), 9)
        XCTAssertEqual(try store.minSequence(chatID: "c1"), 7)
        XCTAssertNil(try store.maxSequence(chatID: "другой"), "в чужом чате курсора нет")
    }

    func testMessageOfOneChatDoesNotLeakIntoAnother() throws {
        try store.upsertMessages(chatID: "c1", payload: Data(#"{"messages":[{"id":"m1","text":"Первое","sequence":1,"is_session_marker":false}]}"#.utf8))
        XCTAssertEqual(try store.messages(chatID: "c2").count, 0)
    }

    // MARK: - Задачи и уведомления

    func testTasksAreReadInTheServerOrder() throws {
        let payload = Data(#"[{"id":"t2","title":"Новее","status":"active","created_at":"2026-10-31 12:00:00"},{"id":"t1","title":"Старее","status":"active","created_at":"2026-10-30 12:00:00"}]"#.utf8)
        try store.upsertTasks(payload)

        let tasks = try store.tasks()
        XCTAssertEqual(tasks.map(\.id), ["t2", "t1"], "порядок — как на сервере: created_at DESC")
    }

    func testRemovedTaskIsDeletedOnlyWhenTheServerSaidSo() throws {
        try store.upsertTasks(Data(#"[{"id":"t1","title":"Живая","status":"active","created_at":"2026-10-31 12:00:00"},{"id":"t2","title":"Удалённая","status":"active","created_at":"2026-10-31 11:00:00"}]"#.utf8))

        try store.removeTasks(ids: ["t2"])
        XCTAssertEqual(try store.tasks().map(\.id), ["t1"])
    }

    func testNotificationsRoundTrip() throws {
        let payload = Data(#"[{"id":"n1","type":"assigned","read":false,"created_at":"2026-10-31 12:00:00"}]"#.utf8)
        try store.upsertNotifications(payload)

        let notifications = try store.notifications()
        XCTAssertEqual(notifications.map(\.id), ["n1"])
        XCTAssertEqual(notifications.first?.read, false)
    }

    // MARK: - Курсоры

    func testSyncStateSurvivesWriteAndRead() {
        store.setSyncState(SyncStateKeys.tasksETag, "W/\"abc-1\"")
        XCTAssertEqual(store.syncState(SyncStateKeys.tasksETag), "W/\"abc-1\"")
    }

    func testSyncStateOfOneKeyDoesNotAffectAnother() {
        store.setSyncState(SyncStateKeys.tasksETag, "etag")
        store.setSyncState(SyncStateKeys.tasksCursor, "cursor")
        XCTAssertEqual(store.syncState(SyncStateKeys.tasksETag), "etag")
        XCTAssertEqual(store.syncState(SyncStateKeys.tasksCursor), "cursor")
    }

    func testClearingTheDatabaseRemovesDataAndCursors() throws {
        try store.upsertChats(Data(#"{"chats":[{"id":"c1","title":"Комната","kind":"group","created_by":"u","members":[]}]}"#.utf8))
        store.setSyncState(SyncStateKeys.tasksETag, "etag")

        try store.clearAll()
        XCTAssertEqual(try store.chats(includeClosed: true).count, 0)
        XCTAssertNil(store.syncState(SyncStateKeys.tasksETag))
    }
}
