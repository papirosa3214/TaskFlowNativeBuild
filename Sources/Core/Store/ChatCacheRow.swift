import Foundation

/// Строка таблицы `chat` из ответа сервера — без GRDB.
///
/// Отдельный файл, потому что правило «что попадает в кеш» проверяется
/// юнит-тестом на macOS, без симулятора: `LocalStore` тянет GRDB, и в такой
/// прогон его не затащить (`Tools/test_chat_cache_restore.py`).
///
/// Зачем тип вообще: модель чата сервер отдаёт только в одну сторону — `RoleChat`
/// умеет `Decodable`, но не `Encodable`. Поэтому «актуальная модель чата» в кеше
/// — это ровно тело ответа сервера (`payload_json`), а не пересобранный из
/// полей объект.
struct ChatCacheRow: Equatable {
    let id: String
    let title: String?
    let kind: String?
    let roomKind: String?
    let updatedAt: String?
    let lastMessageJSON: Data?
    let unreadCount: Int
    /// Значение столбца `archived_at`. `nil` — чат в обычном списке.
    ///
    /// Сервер проставляет `archived_at` и `closed_at` парой (архивация снимает
    /// оба), но столбец один: берём `archived_at`, иначе `closed_at` — иначе
    /// архивный-но-не-закрытый чат оставался бы в обычном списке.
    private(set) var archivedAt: String?
    /// Тело строки — то, что читает экран настоящей моделью `RoleChat`.
    private(set) var payloadJSON: Data

    init?(element: Any) {
        guard let chat = element as? [String: Any],
              let id = Self.string(chat, "id"), !id.isEmpty
        else { return nil }
        self.id = id
        title = Self.string(chat, "title")
        kind = Self.string(chat, "kind")
        roomKind = Self.string(chat, "room_kind")
        updatedAt = Self.string(chat, "updated_at")
        lastMessageJSON = (chat["last_message"] as? [String: Any]).map(Self.data)
        unreadCount = Self.int(chat, "unread_count") ?? 0
        archivedAt = Self.string(chat, "archived_at") ?? Self.string(chat, "closed_at")
        payloadJSON = Self.data(element)
    }

    /// Объект одного чата из тела ответа: `{"chat":{…}}` или сам чат.
    static func chat(in payload: Data) -> [String: Any]? {
        guard let root = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        if let chat = root["chat"] as? [String: Any] { return chat }
        return root["id"] != nil ? root : nil
    }

    /// Строки списка чатов: `{"chats":[…]}`, массив или один `{"chat":{…}}`.
    static func rows(inList payload: Data) -> [ChatCacheRow] {
        guard let root = try? JSONSerialization.jsonObject(with: payload) else { return [] }
        let list: [Any]
        if let object = root as? [String: Any] {
            if let chats = object["chats"] as? [Any] {
                list = chats
            } else if let chat = object["chat"] as? [String: Any] {
                list = [chat]
            } else {
                list = []
            }
        } else {
            list = (root as? [Any]) ?? []
        }
        return list.compactMap(ChatCacheRow.init(element:))
    }

    /// Строка после ответа сервера «чат больше не в архиве».
    ///
    /// Тело ответа сервера главнее кеша: это единственный источник настоящей
    /// модели — закрытый чат уже закрыт не будет. Тела нет (старый сервер) или
    /// оно не разобралось — берём то, что лежит, и снимаем в нём признаки
    /// архива и закрытия: без этого восстановленный чат считался закрытым
    /// (`RoleChat.isArchived`) и рисовался приглушённым.
    static func restored(stored: Data?, serverBody: Data?) -> ChatCacheRow? {
        let model = serverBody.flatMap(chat(in:)) ?? stored.flatMap(chat(in:))
        guard var row = model.flatMap(ChatCacheRow.init(element:)) else { return nil }
        row.payloadJSON = withoutArchiveFlags(row.payloadJSON)
        row.archivedAt = nil
        return row
    }

    /// Тело модели без `archived_at` и `closed_at`.
    static func withoutArchiveFlags(_ payload: Data) -> Data {
        guard var object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return payload }
        let keys = ["archived_at", "closed_at"]
        guard keys.contains(where: { object[$0] != nil }) else { return payload }
        for key in keys { object.removeValue(forKey: key) }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? payload
    }

    // MARK: - Разбор JSON

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

    /// Сырые байты элемента — чтобы в базе лежал именно ответ сервера.
    private static func data(_ element: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: element)) ?? Data()
    }
}
