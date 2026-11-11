import Foundation
import GRDB

/// Стор локальной базы: читает то, что сервер уже отдал, и пишет ответы
/// сервера как есть.
///
/// Правила хранения (общие для всех таблиц):
/// - **Ключ — `id`.** Запись только обновляется (upsert по `id`). Сообщение
///   удаляется только когда его отозвали или удалил владелец (05.11.2026):
///   экран чата показывает базу, и без удаления оно вернулось бы в ленту.
/// - **`payload_json` — сырой JSON сервера.** Экран декодирует его один раз
///   при чтении. Новое поле на сервере не ломает базу: старое тело просто
///   не содержит этого поля.
/// - **Служебные столбцы** (`title`, `kind`, `unread_count`, `sequence`…) —
///   копия нужных полей из JSON. По ним сортировка и курсоры, чтобы не
///   разбирать JSON ради одного числа.
///
/// Класс не `@MainActor`: база общая для фоновой синхронизации и экранов.
/// GRDB сам разрулит доступ — `DatabaseQueue` безопасна из любых потоков.
final class LocalStore: @unchecked Sendable {
    static let shared = LocalStore()

    private let database = LocalDatabase.shared

    /// Через протокол `DatabaseWriter`: переход `LocalDatabase` на
    /// `DatabasePool` (WAL) не потребует правок стора.
    private var queue: any DatabaseWriter { database.queue }

    private init() {}

    // MARK: - Чаты

    /// Записать ответ `GET /api/chats` (`{"chats":[…]}`).
    func upsertChats(_ payload: Data) throws {
        guard let chats = Self.array(in: payload, key: "chats") else { return }
        try queue.write { db in
            for element in chats {
                guard let chat = element as? [String: Any],
                      let id = Self.string(chat, "id"), !id.isEmpty
                else { continue }
                let raw = Self.data(element)
                let lastMessage = chat["last_message"].flatMap { value -> Data? in
                    guard value is [String: Any] else { return nil }
                    return Self.data(value)
                }
                let arguments: StatementArguments = [
                    "id": id,
                    "title": Self.string(chat, "title"),
                    "kind": Self.string(chat, "kind"),
                    "room_kind": Self.string(chat, "room_kind"),
                    "updated_at": Self.string(chat, "updated_at"),
                    "last_message_json": lastMessage,
                    "unread_count": Self.int(chat, "unread_count") ?? 0,
                    "archived_at": Self.string(chat, "closed_at"),
                    "payload_json": raw,
                ]
                try db.execute(
                    sql: """
                    INSERT INTO chat
                      (id, title, kind, room_kind, updated_at, last_message_json,
                       unread_count, archived_at, payload_json)
                    VALUES
                      (:id, :title, :kind, :room_kind, :updated_at, :last_message_json,
                       :unread_count, :archived_at, :payload_json)
                    ON CONFLICT(id) DO UPDATE SET
                      title = excluded.title,
                      kind = excluded.kind,
                      room_kind = excluded.room_kind,
                      updated_at = excluded.updated_at,
                      last_message_json = excluded.last_message_json,
                      unread_count = excluded.unread_count,
                      archived_at = excluded.archived_at,
                      payload_json = excluded.payload_json
                    """,
                    arguments: arguments
                )
            }
        }
    }

    /// Чаты из базы. Порядок — как на сервере: по свежести.
    /// Убрать сессию из списка на телефоне — спрятать, а не стереть.
    ///
    /// Правило «ничего не удаляем» выше — про сообщения и историю, но и
    /// строку чата терять нельзя: закрытая сессия должна оставаться в
    /// «Показать закрытые» даже без сети. Поэтому «убрать из списка» — это
    /// archived_at, ровно как на сервере (lib/chatArchive.ts): сессия уходит
    /// из обычного списка и остаётся доступной в закрытых.
    ///
    /// Зачем это вообще: закрытый чат сервер в `GET /api/chats` уже не
    /// отдаёт, а при ответе 304 («список не изменился») экран берёт список
    /// из этой таблицы — и «удалённая» сессия возвращалась после каждого
    /// перезапуска. Владелец 31.10.2026: «удаляю сессию из списка, она не
    /// удаляется».
    func hideChat(id: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE chat SET archived_at = COALESCE(archived_at, datetime('now')) WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Вернуть чат из архива в кеше: обратная операция к `hideChat`.
    func showChat(id: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE chat SET archived_at = NULL, closed_at = NULL WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Спрятать всё, чего не было в полном ответе сервера.
    ///
    /// Зовётся ТОЛЬКО когда пришло тело, а не 304: тогда список — ровно то,
    /// что видит владелец, а всё остальное в таблице — устаревший хвост
    /// (закрытые и убранные сессии, правки с другого устройства). Строки не
    /// стираются: спрятанный чат показывается в «Показать закрытые» и
    /// возвращается сам, если сервер снова отдал его в списке.
    func hideChats(notIn ids: Set<String>) throws {
        try queue.write { db in
            let rows = try String.fetchAll(db, sql: "SELECT id FROM chat WHERE archived_at IS NULL")
            for id in rows where !ids.contains(id) {
                try db.execute(sql: "UPDATE chat SET archived_at = datetime('now') WHERE id = ?", arguments: [id])
            }
        }
    }

    func chats(includeClosed: Bool = false) throws -> [RoleChat] {
        let sql = includeClosed
            ? "SELECT payload_json FROM chat ORDER BY updated_at DESC, id ASC"
            : "SELECT payload_json FROM chat WHERE archived_at IS NULL ORDER BY updated_at DESC, id ASC"
        let rows = try queue.read { db in try Row.fetchAll(db, sql: sql) }
        return rows.compactMap { row in
            guard let raw: Data = row["payload_json"] else { return nil }
            return try? JSONDecoder().decode(RoleChat.self, from: raw)
        }
    }

    /// Один чат по id — без разбора всех остальных.
    func chat(id: String, includeClosed: Bool = false) throws -> RoleChat? {
        let sql = includeClosed
            ? "SELECT payload_json FROM chat WHERE id = ?"
            : "SELECT payload_json FROM chat WHERE id = ? AND archived_at IS NULL"
        let raw = try queue.read { db in try Data.fetchOne(db, sql: sql, arguments: [id]) }
        guard let raw else { return nil }
        return try? JSONDecoder().decode(RoleChat.self, from: raw)
    }

    // MARK: - Сообщения

    /// Записать ответ `GET /api/chats/:id/messages` (`{"messages":[…]}`).
    ///
    /// `sequence` — монотонный номер сообщения, по нему догружаем новые.
    /// Сообщения без `sequence` (старый сервер) пишем с `-1`: они попадут
    /// в историю, но курсор по ним не поедет — догрузка возьмёт их целиком.
    func upsertMessages(chatID: String, payload: Data) throws {
        guard let messages = Self.array(in: payload, key: "messages") else { return }
        try queue.write { db in
            for element in messages {
                guard let message = element as? [String: Any],
                      let id = Self.string(message, "id"), !id.isEmpty
                else { continue }
                let raw = Self.data(element)
                let arguments: StatementArguments = [
                    "id": id,
                    "chat_id": chatID,
                    "sequence": Self.int(message, "sequence") ?? -1,
                    "created_at": Self.string(message, "created_at"),
                    "payload_json": raw,
                ]
                try db.execute(
                    sql: """
                    INSERT INTO message (id, chat_id, sequence, created_at, payload_json)
                    VALUES (:id, :chat_id, :sequence, :created_at, :payload_json)
                    ON CONFLICT(id) DO UPDATE SET
                      chat_id = excluded.chat_id,
                      sequence = excluded.sequence,
                      created_at = excluded.created_at,
                      payload_json = excluded.payload_json
                    """,
                    arguments: arguments
                )
            }
        }
    }

    /// История чата из базы, по возрастанию номера сообщения.
    func messages(chatID: String) throws -> [RoleChatMessage] {
        try queue.read { db in try Self.fetchMessages(db, chatID: chatID) }
    }

    /// Лента чата с подпиской: первое значение — что лежит в базе сейчас,
    /// дальше — после каждой записи в сообщения этого чата.
    ///
    /// Экран чата показывает ровно базу (05.11.2026): любая догрузка —
    /// при открытии, из сокета, в фоне, пока чат закрыт, — пишет сюда, и
    /// сообщение появляется в ленте само. Раньше лента жила своей копией в
    /// памяти, и пришедшее, пока чат был закрыт, на экран не попадало.
    func messageUpdates(chatID: String) -> AsyncValueObservation<[RoleChatMessage]> {
        ValueObservation
            .tracking { db in try Self.fetchMessages(db, chatID: chatID) }
            .removeDuplicates(by: { $0.map(\.id) == $1.map(\.id) })
            .values(in: queue)
    }

    // MARK: - Окно последних сообщений и постраничное чтение

    /// Сколько сообщений чата экран показывает по умолчанию.
    static let defaultMessageWindow = 30

    /// Сырые строки сообщения: сравнение по ним ловит любую правку тела
    /// (текст, `updated_at`, вложения), а не только смену набора id.
    struct RawMessageRow: Equatable, Sendable {
        let id: String
        let sequence: Int
        let payload: Data
    }

    /// Последние `limit` сообщений чата по возрастанию номера. Чтение и
    /// декод — вне главного потока.
    func latestMessages(chatID: String, limit: Int = LocalStore.defaultMessageWindow) async throws -> [RoleChatMessage] {
        let rows = try await queue.read { db in try Self.fetchRawWindow(db, chatID: chatID, limit: limit, beforeSequence: nil) }
        return Self.decode(rows)
    }

    /// Страница истории: `limit` сообщений строго старше `beforeSequence`
    /// (курсор — `sequence` самого старого показанного сообщения), по
    /// возрастанию. Пустой массив — дальше истории в базе нет.
    func messages(chatID: String, beforeSequence: Int, limit: Int = LocalStore.defaultMessageWindow) async throws -> [RoleChatMessage] {
        let rows = try await queue.read { db in try Self.fetchRawWindow(db, chatID: chatID, limit: limit, beforeSequence: beforeSequence) }
        return Self.decode(rows)
    }

    /// Страница истории до сообщения с данным id (его `sequence` берётся из
    /// базы). Неизвестный id — пустой массив.
    func messages(chatID: String, beforeMessageID: String, limit: Int = LocalStore.defaultMessageWindow) async throws -> [RoleChatMessage] {
        let rows = try await queue.read { db -> [RawMessageRow] in
            guard let cursor = try Int.fetchOne(
                db,
                sql: "SELECT sequence FROM message WHERE chat_id = ? AND id = ?",
                arguments: [chatID, beforeMessageID]
            ) else { return [] }
            return try Self.fetchRawWindow(db, chatID: chatID, limit: limit, beforeSequence: cursor)
        }
        return Self.decode(rows)
    }

    /// Окно последних `limit` сообщений чата с подпиской.
    ///
    /// Отличия от `messageUpdates(chatID:)`:
    /// - читаются только последние `limit` строк (индекс `chat_id, sequence`);
    /// - дубликаты отсекаются по сырому телу, поэтому правка сообщения
    ///   (тот же id, новый текст/`updated_at`) доходит до экрана, а запись
    ///   в чужой чат, не изменившая окно, экран не будит;
    /// - выборка и декод JSON идут на фоновой очереди, значения приходят
    ///   в `for await` на том акторе, где их читают (экран — главный).
    ///
    /// GRDB не умеет сузить регион наблюдения по `chat_id` (только по
    /// rowid), поэтому запись в чужой чат перечитывает окно из индекса —
    /// дёшево, — но до декода и до экрана такое событие не доходит.
    func latestMessageUpdates(
        chatID: String,
        limit: Int = LocalStore.defaultMessageWindow
    ) -> AsyncValueObservation<[RoleChatMessage]> {
        ValueObservation
            .tracking { db in try Self.fetchRawWindow(db, chatID: chatID, limit: limit, beforeSequence: nil) }
            .removeDuplicates()
            .map { Self.decode($0) }
            .values(in: queue, scheduling: .async(onQueue: Self.observationQueue))
    }

    private static let observationQueue = DispatchQueue(label: "LocalStore.messages", qos: .userInitiated)

    private static func fetchRawWindow(_ db: Database, chatID: String, limit: Int, beforeSequence: Int?) throws -> [RawMessageRow] {
        let rows: [Row]
        if let beforeSequence {
            rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, sequence, payload_json FROM message
                WHERE chat_id = ? AND sequence < ?
                ORDER BY sequence DESC, id DESC LIMIT ?
                """,
                arguments: [chatID, beforeSequence, max(limit, 0)]
            )
        } else {
            rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, sequence, payload_json FROM message
                WHERE chat_id = ?
                ORDER BY sequence DESC, id DESC LIMIT ?
                """,
                arguments: [chatID, max(limit, 0)]
            )
        }
        return rows.reversed().compactMap { row in
            guard let id: String = row["id"], let raw: Data = row["payload_json"] else { return nil }
            return RawMessageRow(id: id, sequence: row["sequence"] ?? -1, payload: raw)
        }
    }

    private static func decode(_ rows: [RawMessageRow]) -> [RoleChatMessage] {
        let decoder = JSONDecoder()
        return rows.compactMap { try? decoder.decode(RoleChatMessage.self, from: $0.payload) }
    }

    /// Удалить сообщения чата: отозванные и удалённые владельцем. Иначе
    /// лента из базы вернула бы их на экран.
    func deleteMessages(chatID: String, ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try queue.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM message WHERE chat_id = ? AND id = ?", arguments: [chatID, id])
            }
        }
    }

    /// Очистить переписку чата целиком (владелец очистил чат).
    func deleteAllMessages(chatID: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM message WHERE chat_id = ?", arguments: [chatID])
        }
    }

    private static func fetchMessages(_ db: Database, chatID: String) throws -> [RoleChatMessage] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT payload_json FROM message WHERE chat_id = ? ORDER BY sequence ASC, id ASC",
            arguments: [chatID]
        )
        return rows.compactMap { row in
            guard let raw: Data = row["payload_json"] else { return nil }
            return try? JSONDecoder().decode(RoleChatMessage.self, from: raw)
        }
    }

    /// Новейшее сообщение в чате — курсор догрузки.
    func maxSequence(chatID: String) throws -> Int? {
        try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(sequence) FROM message WHERE chat_id = ?", arguments: [chatID])
        }
    }

    /// Самое старое сообщение в чате — курсор догрузки вверх.
    func minSequence(chatID: String) throws -> Int? {
        try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT MIN(sequence) FROM message WHERE chat_id = ?", arguments: [chatID])
        }
    }

    // MARK: - Задачи

    /// Записать ответ `GET /api/tasks` — сервер отдаёт его БЕЗ конверта,
    /// простым массивом.
    func upsertTasks(_ payload: Data) throws {
        guard let tasks = Self.array(in: payload) else { return }
        try queue.write { db in
            for element in tasks {
                try Self.writeTaskRow(db: db, element: element)
            }
        }
    }

    /// Записать полный список задач ВМЕСТЕ с отпечатком и курсором — ОДНОЙ
    /// транзакцией.
    ///
    /// Почему вместе: отпечаток (ETag) — это «тело не менялось». Если он
    /// записан раньше тела (или тело записалось с ошибкой, а отпечаток — нет),
    /// то телефон пришлёт `If-None-Match`, получит 304 БЕЗ тела и останется со
    /// старым или пустым списком навсегда: сервер ведь считает, что тело у
    /// клиента уже есть. Это ровно тот сценарий, из-за которого список на
    /// телефоне расходился с сервером (заметка «Кэш и синхронизация в
    /// мобильных клиентах», раздел 4.2, риск «304 без проверки наличия тела»).
    func applyTaskList(payload: Data, etag: String?, cursor: String?) throws {
        guard let tasks = Self.array(in: payload) else { throw LocalStoreError.unexpectedPayload }
        try queue.write { db in
            var live = Set<String>()
            for element in tasks {
                try Self.writeTaskRow(db: db, element: element)
                if let task = element as? [String: Any], let id = Self.string(task, "id") {
                    live.insert(id)
                }
            }
            // Телефон хранит только ЖИВОЕ. Всё, чего больше нет в живом
            // списке (выполнено, отменено, ушло в архив, удалено), из базы
            // уходит: на сервере оно лежит, а держать вторую копию на телефоне
            // незачем (владелец 02.11.2026).
            let stored = try String.fetchAll(db, sql: "SELECT id FROM task")
            for id in TaskSyncCachePolicy.staleIds(stored: stored, live: live) {
                try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [id])
            }
            try Self.writeSyncState(db: db, key: SyncStateKeys.tasksETag, value: etag)
            try Self.writeSyncState(db: db, key: SyncStateKeys.tasksCursor, value: cursor)
        }
    }

    /// Применить дельту: изменившиеся карточки — перезапись, исчезнувшие —
    /// удаление, курсор — сдвиг. Всё одной транзакцией.
    ///
    /// Курсор сдвигается ТОЛЬКО вместе с применёнными карточками: он означает
    /// «до этого места я догнал», и сдвинуть его раньше — значит потерять
    /// изменение навсегда (сервер больше его не пришлёт).
    ///
    /// `changedPayload` — ответ батча (`{"tasks":[…]}`) в форме списка.
    /// `nil` — карточек в форме списка нет (старый сервер без батч-ручки):
    /// тогда пишем только удаления и курсор, а сами карточки обновятся
    /// полной перечиткой. Класть в базу полную карточку нельзя: у полной
    /// карточки и у строки списка РАЗНЫЕ формы, и в одной базе они разойдутся
    /// по полям.
    func applyTaskDelta(changedPayload: Data?, removedIds: [String], cursor: String?) throws {
        var changed: [Any] = []
        if let changedPayload {
            guard let items = Self.array(in: changedPayload, key: "tasks") else {
                throw LocalStoreError.unexpectedPayload
            }
            changed = items
        }
        try queue.write { db in
            for element in changed {
                try Self.writeTaskRow(db: db, element: element)
            }
            for id in removedIds {
                try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [id])
            }
            try Self.writeSyncState(db: db, key: SyncStateKeys.tasksCursor, value: cursor)
        }
    }

    /// Есть ли в базе карточки.
    ///
    /// Без них условие `If-None-Match` послать нельзя: сервер ответит 304
    /// «список не менялся», а показать будет нечего.
    func hasTasks() -> Bool {
        guard database.isReady else { return false }
        let count = (try? queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task")
        }) ?? 0
        return count > 0
    }

    /// Задачи из базы. Порядок — как на сервере: сначала новые.
    func tasks() throws -> [ApiTask] {
        let rows = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT payload_json FROM task")
        }
        let decoded = rows.compactMap { row -> ApiTask? in
            guard let raw: Data = row["payload_json"] else { return nil }
            return try? JSONDecoder().decode(ApiTask.self, from: raw)
        }
        // Порядок сервера — `created_at DESC`; служебного столбца с этим
        // полем в таблице нет, поэтому сортируем после разбора.
        return decoded.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    /// Удалить задачи, о которых сервер ЯВНО сказал, что их больше нет
    /// (`removed_ids` в дельте). Только это и только это: молчаливого
    /// удаления в локальной базе нет — иначе история рассыпалась бы сама.
    func removeTasks(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try queue.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [id])
            }
        }
    }

    // MARK: - Уведомления

    /// Записать ответ `GET /api/notifications` — тоже простой массив.
    func upsertNotifications(_ payload: Data) throws {
        guard let items = Self.array(in: payload) else { return }
        try queue.write { db in
            for element in items {
                guard let item = element as? [String: Any],
                      let id = Self.string(item, "id"), !id.isEmpty
                else { continue }
                let arguments: StatementArguments = [
                    "id": id,
                    "is_read": Self.bool(item, "read") ?? false,
                    "created_at": Self.string(item, "created_at"),
                    "payload_json": Self.data(element),
                ]
                try db.execute(
                    sql: """
                    INSERT INTO notification (id, is_read, created_at, payload_json)
                    VALUES (:id, :is_read, :created_at, :payload_json)
                    ON CONFLICT(id) DO UPDATE SET
                      is_read = excluded.is_read,
                      created_at = excluded.created_at,
                      payload_json = excluded.payload_json
                    """,
                    arguments: arguments
                )
            }
        }
    }

    /// Уведомления из базы, свежие сверху.
    func notifications() throws -> [ApiNotification] {
        let rows = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT payload_json FROM notification ORDER BY created_at DESC, id ASC")
        }
        return rows.compactMap { row in
            guard let raw: Data = row["payload_json"] else { return nil }
            return try? JSONDecoder().decode(ApiNotification.self, from: raw)
        }
    }

    // MARK: - Курсоры и отпечатки

    /// Очистить базу целиком — при выходе из аккаунта.
    ///
    /// На одном телефоне могут войти разные люди: чужая переписка и чужие
    /// задачи не должны оставаться на устройстве после выхода. Локальная
    /// история — это копия чужих данных, а не личное хранилище.
    func clearAll() throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM chat")
            try db.execute(sql: "DELETE FROM message")
            try db.execute(sql: "DELETE FROM task")
            try db.execute(sql: "DELETE FROM notification")
            try db.execute(sql: "DELETE FROM sync_state")
        }
    }

    /// Отпечаток/курсор из `sync_state`. Ключи — в `SyncStateKeys`.
    func syncState(_ key: String) -> String? {
        guard database.isReady else { return nil }
        guard let value = try? queue.read({ db in
            try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE state_key = ?", arguments: [key])
        }) else { return nil }
        return value
    }

    /// Записать отпечаток/курсор.
    func setSyncState(_ key: String, _ value: String?) {
        guard database.isReady else { return }
        try? queue.write { db in
            if let value {
                try db.execute(
                    sql: """
                    INSERT INTO sync_state (state_key, value) VALUES (:key, :value)
                    ON CONFLICT(state_key) DO UPDATE SET value = excluded.value
                    """,
                    arguments: ["key": key, "value": value]
                )
            } else {
                try db.execute(sql: "DELETE FROM sync_state WHERE state_key = ?", arguments: [key])
            }
        }
    }

    // MARK: - Запись строк

    /// Строка карточки — по элементу ответа сервера.
    ///
    /// В базу ложится СЫРОЙ элемент ответа: новая схема сервера базу не
    /// ломает — старое тело просто не содержит нового поля.
    private static func writeTaskRow(db: Database, element: Any) throws {
        guard let task = element as? [String: Any],
              let id = Self.string(task, "id"), !id.isEmpty
        else { return }
        let arguments: StatementArguments = [
            "id": id,
            "updated_at": Self.string(task, "updated_at"),
            "payload_json": Self.data(element),
        ]
        try db.execute(
            sql: """
            INSERT INTO task (id, updated_at, payload_json)
            VALUES (:id, :updated_at, :payload_json)
            ON CONFLICT(id) DO UPDATE SET
              updated_at = excluded.updated_at,
              payload_json = excluded.payload_json
            """,
            arguments: arguments
        )
    }

    /// Отпечаток или курсор — внутри той же транзакции, что и тело.
    ///
    /// Пишется только через этот помощник: отдельная запись мимо транзакции
    /// тела — это и есть «отпечаток есть, тела нет».
    private static func writeSyncState(db: Database, key: String, value: String?) throws {
        if let value {
            try db.execute(
                sql: """
                INSERT INTO sync_state (state_key, value) VALUES (:key, :value)
                ON CONFLICT(state_key) DO UPDATE SET value = excluded.value
                """,
                arguments: ["key": key, "value": value]
            )
        } else {
            try db.execute(sql: "DELETE FROM sync_state WHERE state_key = ?", arguments: [key])
        }
    }

    // MARK: - Разбор JSON

    /// Массив из тела ответа: либо сам ответ массив, либо поле-конверт.
    private static func array(in payload: Data, key: String? = nil) -> [Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: payload) else { return nil }
        if let key {
            guard let object = root as? [String: Any] else { return nil }
            return object[key] as? [Any]
        }
        return root as? [Any]
    }

    private static func string(_ object: [String: Any], _ key: String) -> String? {
        if let value = object[key] as? String { return value }
        if let value = object[key] as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int(_ object: [String: Any], _ key: String) -> Int? {
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? NSNumber { return value.intValue }
        return nil
    }

    private static func bool(_ object: [String: Any], _ key: String) -> Bool? {
        if let value = object[key] as? Bool { return value }
        if let value = object[key] as? NSNumber { return value.boolValue }
        return nil
    }

    /// Сырые байты элемента — чтобы в базу лёг именно ответ сервера.
    private static func data(_ element: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: element)) ?? Data()
    }
}

/// Форма ответа сервера не та, которую ждал клиент.
///
/// Раньше такой разбор молча проглатывался (`try?`), и телефон продолжал
/// считать, что данные записаны. Теперь это ошибка, которую видно.
enum LocalStoreError: Error {
    case unexpectedPayload
}

/// Ключи `sync_state`. Одно место — иначе курсор и отпечаток разъедутся
/// по разным файлам и переживут перезапуск по-разному.
enum SyncStateKeys {
    /// ETag списка задач: `GET /api/tasks` отвечает 304, если не менялся.
    static let tasksETag = "tasks.etag"
    /// Курсор дельты задач (`X-TaskFlow-Sync-Cursor`).
    static let tasksCursor = "tasks.cursor"
    /// ETag списка чатов: `GET /api/chats` отвечает 304, если не менялся.
    static let chatsETag = "chats.etag"
    /// Умеет ли сервер постраничную выдачу сообщений (`has_more`).
    /// Старый сервер отдаёт весь чат целиком — тогда догружать по частям
    /// нельзя, и клиент это запоминает здесь.
    static let chatsPaging = "chats.paging"
    /// Курсор сообщений по чату: `messages.cursor.<chatID>`.
    static func messagesCursor(chatID: String) -> String { "messages.cursor.\(chatID)" }
}
