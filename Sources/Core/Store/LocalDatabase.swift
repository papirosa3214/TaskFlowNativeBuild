import Foundation
import GRDB

/// Локальная база TaskFlow — зеркало того, что сервер уже отдавал.
///
/// Зачем она: телефон должен показывать список задач и переписку сразу,
/// без сети, и не тянуть полный список задач при каждом запуске (402 КБ
/// в gzip — см. `docs/2026-10-25-traffic-trim.md`). Поэтому здесь лежит
/// и СЫРОЙ ответ сервера (`payload_json`), и отпечатки (`sync_state`:
/// ETag и курсоры), которые переживают перезапуск приложения.
///
/// `DatabasePool` (WAL): чтение ленты с главного потока не ждёт фоновую
/// запись синхронизации (аудит плавности чата 11.11.2026; до этого был
/// `DatabaseQueue`, и открытие чата стояло за записью сети).
final class LocalDatabase {
    static let shared = LocalDatabase()

    let queue: any DatabaseWriter

    /// Создалась ли база: если миграция не прошла, приложение продолжает
    /// работать на сети (LocalStore вернёт пустые списки), но не падает.
    private(set) var isReady = false

    private init() {
        queue = Self.makeQueue()
        do {
            try Self.migrator.migrate(queue)
            isReady = true
        } catch {
            // База — не критичная часть приложения: сеть работает и без неё.
            // Логируем и едем дальше, экраны покажут скелет и подтянут
            // данные из сети.
            print("[LocalDatabase] миграция не прошла: \(error)")
        }
    }

    // MARK: - Файл базы

    private static func makeQueue() -> any DatabaseWriter {
        let manager = FileManager.default
        let base = (try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? manager.temporaryDirectory
        let folder = base.appendingPathComponent("TaskFlow", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("taskflow.sqlite").path
        if let pool = try? DatabasePool(path: path) { return pool }
        // Файловая база не открылась — работаем в памяти: список пустой, но
        // приложение живо и не падает на старте.
        // swiftlint:disable:next force_try
        return try! DatabaseQueue()
    }

    // MARK: - Схема

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // v1 — исходная схема. Правки идём отдельными миграциями: правило
        // «одно место на одно значение» и здесь — старые базы не трогаем.
        migrator.registerMigration("v1") { db in
            // Чаты: список переписок и комнат.
            try db.create(table: "chat") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text)
                t.column("kind", .text)
                t.column("room_kind", .text)
                t.column("updated_at", .text)
                t.column("last_message_json", .blob)
                t.column("unread_count", .integer).notNull().defaults(to: 0)
                t.column("archived_at", .text)
                // Сырой ответ сервера по этому чату целиком. Экран
                // декодирует его один раз при чтении — и новая поле сервера
                // не ломает базу.
                t.column("payload_json", .blob).notNull()
            }

            // Сообщения чата. `sequence` — монотонный номер сообщения
            // (на сервере это rowid таблицы сообщений): он и есть курсор
            // догрузки, переиспользуется он никогда.
            try db.create(table: "message") { t in
                t.column("id", .text).primaryKey()
                t.column("chat_id", .text).notNull()
                t.column("sequence", .integer).notNull()
                t.column("created_at", .text)
                t.column("payload_json", .blob).notNull()
            }
            try db.create(
                index: "message_on_chat_sequence",
                on: "message",
                columns: ["chat_id", "sequence"]
            )

            // Задачи: список задач целиком (сервер отдаёт его одним массивом).
            try db.create(table: "task") { t in
                t.column("id", .text).primaryKey()
                t.column("updated_at", .text)
                t.column("payload_json", .blob).notNull()
            }

            // Уведомления.
            try db.create(table: "notification") { t in
                t.column("id", .text).primaryKey()
                t.column("is_read", .boolean).notNull().defaults(to: false)
                t.column("created_at", .text)
                t.column("payload_json", .blob).notNull()
            }

            // Курсоры и отпечатки: ETag списка задач, курсор дельты задач,
            // курсор сообщений по каждому чату, отпечаток списка чатов.
            // Ключ назван `state_key`, а не `key`: KEY — зарезервированное
            // слово SQLite, и такой столбец пришлось бы писать в кавычках
            // в каждом запросе.
            try db.create(table: "sync_state") { t in
                t.column("state_key", .text).primaryKey()
                t.column("value", .text)
            }
        }

        return migrator
    }
}
