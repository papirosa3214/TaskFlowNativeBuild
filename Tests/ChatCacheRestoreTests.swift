import Foundation
import XCTest
@testable import TaskFlow

/// Возврат чата из архива в локальном кеше (аудит 14.11.2026).
///
/// Одного столбца `archived_at` мало: экран читает `payload_json` — модель
/// чата, — и признаки архива живут в нём же (`archived_at`, `closed_at`).
/// Поэтому тест смотрит обе половины строки: чат снова в обычном списке
/// (столбец) и его модель больше не архивная и не закрытая (тело).
///
/// Разбор ответа сервера живёт в `ChatCacheRow` без GRDB: эту часть можно
/// прогнать без симулятора — `Tools/test_chat_cache_restore.py`.
final class ChatCacheRestoreTests: XCTestCase {
    /// Как строка лежит в кеше после архивации: сервер проставил оба признака.
    private let archived = Data(#"""
    {"id":"c1","title":"Архивная","kind":"group","created_by":"u","members":[],"archived_at":"2026-11-13 10:00:00","closed_at":"2026-11-13 10:00:00"}
    """#.utf8)

    /// Ответ сервера `POST /chats/{id}/unarchive`: чат снова обычный.
    private let serverAnswer = Data(#"""
    {"chat":{"id":"c1","title":"Архивная","kind":"group","created_by":"u","members":[],"archived_at":null,"closed_at":null,"unread_count":0}}
    """#.utf8)

    func testRestoredChatIsVisibleAndNoLongerArchived() throws {
        let row = try XCTUnwrap(ChatCacheRow.restored(stored: archived, serverBody: serverAnswer))

        XCTAssertEqual(row.id, "c1")
        XCTAssertNil(row.archivedAt, "чат должен вернуться в обычный список")

        let model = try XCTUnwrap(ChatCacheRow.chat(in: row.payloadJSON))
        XCTAssertNil(model["closed_at"], "модель чата не должна быть закрытой")
        XCTAssertNil(model["archived_at"], "модель чата не должна быть архивной")
        XCTAssertEqual(model["title"] as? String, "Архивная")
    }

    /// Старый сервер тела не прислал — снимаем признаки архива в том, что уже
    /// лежит, иначе восстановленный чат остаётся приглушённым и «закрытым».
    func testRestoreWithoutServerBodyDropsStaleArchiveFlags() throws {
        let row = try XCTUnwrap(ChatCacheRow.restored(stored: archived, serverBody: nil))

        XCTAssertNil(row.archivedAt)

        let model = try XCTUnwrap(ChatCacheRow.chat(in: row.payloadJSON))
        XCTAssertNil(model["closed_at"])
        XCTAssertNil(model["archived_at"])
        XCTAssertEqual(model["title"] as? String, "Архивная", "остальные поля не теряются")
    }

    func testServerBodyWinsOverTheCache() throws {
        let body = Data(#"{"chat":{"id":"c1","title":"Новое имя","kind":"group","created_by":"u","members":[]}}"#.utf8)

        let row = try XCTUnwrap(ChatCacheRow.restored(stored: archived, serverBody: body))

        XCTAssertEqual(row.title, "Новое имя")
        XCTAssertNil(row.archivedAt)
    }

    func testUnknownChatYieldsNoRow() {
        XCTAssertNil(ChatCacheRow.restored(stored: Data("не json".utf8), serverBody: Data("{}".utf8)))
    }

    /// Проекция в столбец при обычной синхронизации списка не поменялась.
    func testListProjectsArchiveFlagIntoTheColumn() {
        let rows = ChatCacheRow.rows(inList: Data(#"""
        {"chats":[{"id":"a","closed_at":"2026-11-13 10:00:00"},{"id":"b"}]}
        """#.utf8))

        XCTAssertEqual(rows.map(\.id), ["a", "b"])
        XCTAssertEqual(rows.first?.archivedAt, "2026-11-13 10:00:00")
        XCTAssertNil(rows.last?.archivedAt)
    }
}
