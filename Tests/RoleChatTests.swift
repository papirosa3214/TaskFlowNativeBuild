import Foundation
import XCTest
@testable import TaskFlow

/// Формы JSON соответствуют ответам `/api/chats` и `/api/chats/:id/messages`.
final class RoleChatTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testServerSequenceOrdersOutOfOrderSocketMessagesWithEqualTimestamps() throws {
        let messages = try decode([RoleChatMessage].self, #"[{"id":"reply","text":"Ответ","from_user_id":"u-secretary","created_at":"2026-10-11 14:20:50","is_session_marker":false,"sequence":42},{"id":"question","text":"Вопрос","created_at":"2026-10-11 14:20:50","is_session_marker":false,"sequence":41}]"#)
        XCTAssertEqual(RoleChatMessageOrder.sorted(messages).map(\.id), ["question", "reply"])
    }

    func testOnlyReplyToCurrentTriggerCompletesLiveTurn() throws {
        let turn = try decode(RoleChatLiveTurn.self, #"{"chat_id":"chat-secretary","user_id":"u-secretary","name":"Помощник владельца","started_at":"2026-10-11T14:20:50.900Z","trigger_message_id":"question-2","items":[]}"#)
        let messages = try decode([RoleChatMessage].self, #"[{"id":"old","text":"Старый ответ","from_user_id":"u-secretary","created_at":"2026-10-11 14:20:51","is_session_marker":false,"reply_to_message_id":"question-1"},{"id":"current","text":"Ответ","from_user_id":"u-secretary","created_at":"2026-10-11 14:20:50","is_session_marker":false,"reply_to_message_id":"question-2"}]"#)
        XCTAssertFalse(turn.isCompleted(by: messages[0]))
        XCTAssertTrue(turn.isCompleted(by: messages[1]))
    }

    func testLegacyCompletionWithinSameSQLiteSecond() throws {
        let turn = try decode(RoleChatLiveTurn.self, #"{"chat_id":"c","user_id":"r","name":"Роль","started_at":"2026-10-11T14:20:50.900Z","items":[]}"#)
        let message = try decode(RoleChatMessage.self, #"{"id":"m","text":"Готово","from_user_id":"r","created_at":"2026-10-11 14:20:50","is_session_marker":false}"#)
        XCTAssertTrue(turn.isCompleted(by: message))
    }

    func testStaleRESTSnapshotCannotRemoveOrReplaceNewSocketMessage() throws {
        let old = try decode([RoleChatMessage].self, #"[{"id":"q","text":"Вопрос","sequence":1,"is_session_marker":false},{"id":"a","text":"Старый текст","sequence":2,"is_session_marker":false}]"#)
        let current = try decode([RoleChatMessage].self, #"[{"id":"q","text":"Вопрос","sequence":1,"is_session_marker":false},{"id":"a","text":"Новый текст","sequence":2,"is_session_marker":false},{"id":"b","text":"Получен по сокету","sequence":3,"is_session_marker":false}]"#)
        let merged = RoleChatMessageOrder.mergingSnapshot(old, current: current, receivedAfterRequest: ["a", "b"])
        XCTAssertEqual(merged.map(\.text), ["Вопрос", "Новый текст", "Получен по сокету"])
        let deleted = RoleChatMessageOrder.mergingSnapshot([], current: current, receivedAfterRequest: [])
        XCTAssertTrue(deleted.isEmpty)
    }

    func testGroupChatDecodesServerFieldsAndMembers() throws {
        let chat = try decode(RoleChat.self, #"""
        {
          "id": "chat-1", "title": null, "kind": "group", "created_by": "owner-1",
          "task_id": null, "created_at": "2026-09-21T10:00:00.000Z",
          "members": [
            { "id": "owner-1", "name": "Максим", "role": "owner", "type": "human",
              "avatar_color": null, "avatar_url": null, "initials": "М" },
            { "id": "role_architect", "name": "Архитектор", "role": "architect",
              "type": "agent", "avatar_color": "#345678", "avatar_url": "/avatar/a.png",
              "initials": "А" },
            { "id": "role_reviewer", "name": "Ревьюер", "role": "reviewer",
              "type": "agent", "avatar_color": null, "avatar_url": null,
              "initials": "Р" }
          ],
          "last_message": {
            "text": "Проверил задачу", "created_at": "2026-09-21T10:01:00.000Z",
            "from_user_id": "role_reviewer"
          }
        }
        """#)

        XCTAssertEqual(chat.id, "chat-1")
        XCTAssertNil(chat.title)
        XCTAssertEqual(chat.kind, "group")
        XCTAssertEqual(chat.createdBy, "owner-1")
        XCTAssertEqual(chat.members.map(\.id), ["owner-1", "role_architect", "role_reviewer"])
        XCTAssertEqual(chat.members[1].avatarColor, "#345678")
        XCTAssertEqual(chat.members[1].avatarURL, "/avatar/a.png")
        XCTAssertEqual(chat.members[1].initials, "А")
        XCTAssertEqual(chat.lastMessage?.text, "Проверил задачу")
        XCTAssertEqual(chat.lastMessage?.fromUserID, "role_reviewer")
        XCTAssertEqual(chat.displayTitle(excluding: "owner-1"), "Архитектор, Ревьюер")
    }

    func testTitleAndParticipantFallbacks() throws {
        let named = try decode(RoleChat.self, #"""
        {"id":"chat-2","title":"План релиза","kind":"group","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"},
                    {"id":"role_architect","name":"Архитектор"}],"last_message":null}
        """#)
        XCTAssertEqual(named.displayTitle(excluding: "owner-1"), "План релиза")
        XCTAssertNil(named.lastMessage)
        XCTAssertNil(named.members[1].avatarURL)

        let untitled = try decode(RoleChat.self, #"""
        {"id":"chat-3","title":"  \n ","kind":"group","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"},
                    {"id":"role_architect","name":" Архитектор "},
                    {"id":"role_reviewer","name":"Ревьюер"}]}
        """#)
        XCTAssertEqual(untitled.displayTitle(excluding: "owner-1"), "Архитектор, Ревьюер")
        XCTAssertNil(untitled.lastMessage)

        let emptyGroup = try decode(RoleChat.self, #"""
        {"id":"chat-4","title":null,"kind":"group","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"}]}
        """#)
        XCTAssertEqual(emptyGroup.displayTitle(excluding: "owner-1"), "Групповой чат")
    }

    func testDirectChatUsesOtherMemberName() throws {
        let chat = try decode(RoleChat.self, #"""
        {"id":"chat-5","title":null,"kind":"direct","created_by":"owner-1",
         "members":[{"id":"owner-1","name":"Максим"},
                    {"id":"role_secretary","name":"Помощник владельца"}]}
        """#)
        XCTAssertEqual(chat.displayTitle(excluding: "owner-1"), "Помощник владельца")
    }

    func testMessageDecodesServerAuthorFields() throws {
        let message = try decode(RoleChatMessage.self, #"""
        {
          "id": "msg-1", "chat_id": "chat-1", "from_user_id": "role_reviewer",
          "from_user_name": "Ревьюер", "from_user_color": "#123456",
          "from_user_avatar_url": "/avatar/reviewer.png", "from_user_initials": "Р",
          "text": "Проверил задачу", "created_at": "2026-09-21T10:01:00.000Z",
          "attachments": [], "is_session_marker": false
        }
        """#)

        XCTAssertEqual(message.id, "msg-1")
        XCTAssertEqual(message.chatID, "chat-1")
        XCTAssertEqual(message.fromUserID, "role_reviewer")
        XCTAssertEqual(message.fromUserName, "Ревьюер")
        XCTAssertEqual(message.fromUserColor, "#123456")
        XCTAssertEqual(message.fromUserAvatarURL, "/avatar/reviewer.png")
        XCTAssertEqual(message.fromUserInitials, "Р")
        XCTAssertEqual(message.text, "Проверил задачу")
        XCTAssertEqual(message.createdAt, "2026-09-21T10:01:00.000Z")
    }

    func testMessageAcceptsNullableAuthor() throws {
        let message = try decode(RoleChatMessage.self, #"""
        {"id":"msg-2","chat_id":"chat-1","from_user_id":null,
         "from_user_name":null,"from_user_color":null,"from_user_avatar_url":null,
         "from_user_initials":null,"text":"Системное сообщение","created_at":null,
         "is_session_marker":false}
        """#)
        XCTAssertNil(message.fromUserID)
        XCTAssertNil(message.fromUserName)
        XCTAssertNil(message.fromUserAvatarURL)
        XCTAssertNil(message.createdAt)
    }
}

/// Разделители дней в ленте переписки (владелец 03.10.2026): где начинается
/// новый день и как он называется. Даты — по МОСКОВСКОМУ календарю (общее
/// правило проекта: все даты в Europe/Moscow), поэтому тесты строят моменты
/// московским календарём, а не константами.
final class ChatDayLabelTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return cal
    }()

    private func moment(daysAgo: Int, hour: Int = 12) -> Date {
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -daysAgo, to: start)!
            .addingTimeInterval(TimeInterval(hour * 3600))
    }

    /// `created_at` в том же sqlite-UTC формате, что присылает сервер.
    private func raw(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    func testLabelsTodayYesterdayAndWeekday() {
        XCTAssertEqual(ChatDayLabel.label(moment(daysAgo: 0)), "Сегодня")
        XCTAssertEqual(ChatDayLabel.label(moment(daysAgo: 1)), "Вчера")
        let threeDaysAgo = ChatDayLabel.label(moment(daysAgo: 3))
        XCTAssertFalse(threeDaysAgo.isEmpty)
        XCTAssertNotEqual(threeDaysAgo, "Сегодня")
        XCTAssertNotEqual(threeDaysAgo, "Вчера")
        // Слова не содержат цифр — это название дня недели, а не дата.
        XCTAssertFalse(threeDaysAgo.contains(where: { $0.isNumber }))
    }

    func testLabelOlderThanWeekHasDayAndMonth() {
        let label = ChatDayLabel.label(moment(daysAgo: 20))
        let parts = label.split(separator: " ")
        XCTAssertGreaterThanOrEqual(parts.count, 2)
        XCTAssertTrue(parts[0].allSatisfy(\.isNumber), "первым идёт число дня: \(label)")
    }

    func testLabelParsesServerTimestampAndRejectsGarbage() {
        let today = moment(daysAgo: 0, hour: 13)
        // Формат сервера — sqlite UTC; разбор возвращает тот же момент, поэтому
        // ключ дня совпадает независимо от таймзоны устройства.
        XCTAssertEqual(ChatDayLabel.label(raw: raw(today)), "Сегодня")
        XCTAssertEqual(ChatDayLabel.dayKey(raw: raw(today)), ChatDayLabel.dayKey(today))
        XCTAssertNil(ChatDayLabel.label(raw: nil))
        XCTAssertNil(ChatDayLabel.label(raw: ""))
        XCTAssertNil(ChatDayLabel.label(raw: "не дата"))
        XCTAssertNil(ChatDayLabel.dayKey(raw: "не дата"))
    }

    func testDayStartsMarksFirstMessageAndEachNewDay() {
        let messages = [
            raw(moment(daysAgo: 2)),  // 0 — первый день
            raw(moment(daysAgo: 2)),
            raw(moment(daysAgo: 1)),  // 2 — смена дня
            raw(moment(daysAgo: 0)),  // 3 — смена дня
            raw(moment(daysAgo: 0)),
        ]
        XCTAssertEqual(ChatDayMarker.dayStarts(in: messages, createdAt: \.self), [0, 2, 3])
    }

    /// Сообщение без даты (метка сессии, локальное «в пути») не открывает новый
    /// день и не обрывает текущий.
    func testDayStartsIgnoresMessagesWithoutDate() {
        let today = raw(moment(daysAgo: 0))
        let messages: [String?] = [nil, today, nil, today]
        XCTAssertEqual(ChatDayMarker.dayStarts(in: messages, createdAt: \.self), [1])
    }

    func testDayStartsEmptyWhenHistoryHasNoDates() {
        let messages: [String?] = [nil, nil]
        XCTAssertTrue(ChatDayMarker.dayStarts(in: messages, createdAt: \.self).isEmpty)
    }

    /// Граница суток — московская, а не таймзона устройства: сообщение в
    /// 23:30 по Москве относится к СЕГОДНЯШНЕМУ дню, даже если UTC-дата
    /// сервера у него уже «завтра».
    func testDayBoundaryIsMoscowNotDevice() {
        // 2026-10-21 23:30 UTC = 2026-10-22 02:30 МСК → это уже 22 октября.
        XCTAssertEqual(ChatDayLabel.dayKey(raw: "2026-10-21 23:30:00"), "2026-10-22")
        // 2026-10-21 20:30 UTC = 2026-10-21 23:30 МСК → ещё 21 октября.
        XCTAssertEqual(ChatDayLabel.dayKey(raw: "2026-10-21 20:30:00"), "2026-10-21")
    }
}

/// Идентичность строки ленты и порядок сообщений (владелец 22.10.2026:
/// «текста нет, но он всё равно где-то», сообщения встают криво по времени).
final class RoleChatFeedIdentityTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// Шесть строк от одной роли в ответ на одно сообщение (в живой базе
    /// такое есть: ответ роли + служебные строки координации). Прежний id
    /// строки строился как «reply:автор:на что ответ» — у всех шести он был
    /// ОДИН, и SwiftUI переиспользовал строки: пузыри менялись местами, текст
    /// пропадал, лента прыгала.
    func testRowIDIsUniqueForSeveralMessagesFromSameAuthorOnSameTrigger() throws {
        let messages = try decode([RoleChatMessage].self, #"[{"id":"m1","text":"Ответ","from_user_id":"role_code_orchestrator","created_at":"2026-10-21 13:19:39","is_session_marker":false,"reply_to_message_id":"q1","sequence":10},{"id":"m2","text":"Ответ получен","from_user_id":"role_code_orchestrator","created_at":"2026-10-21 13:19:39","is_session_marker":false,"reply_to_message_id":"q1","kind":"system","sequence":11},{"id":"m3","text":"Ход завершился ошибкой","from_user_id":"role_code_orchestrator","created_at":"2026-10-21 13:19:39","is_session_marker":false,"reply_to_message_id":"q1","kind":"system","sequence":12},{"id":"m4","text":"Ответ","from_user_id":"role_code_orchestrator","created_at":"2026-10-21 13:19:39","is_session_marker":false,"reply_to_message_id":"q1","sequence":13},{"id":"m5","text":"Ответ получен","from_user_id":"role_code_orchestrator","created_at":"2026-10-21 13:19:40","is_session_marker":false,"reply_to_message_id":"q1","kind":"system","sequence":14},{"id":"m6","text":"Ответ получен","from_user_id":"role_code_orchestrator","created_at":"2026-10-21 13:21:59","is_session_marker":false,"reply_to_message_id":"q1","kind":"system","sequence":15}]"#)
        let ids = messages.map { RoleChatRowID.message($0.id) }
        XCTAssertEqual(Set(ids).count, 6, "у строк ленты должен быть свой id")
        // Прежняя формула давала один id на все шесть строк — это и ломало ленту.
        let legacy = Set(messages.map { "reply:\($0.fromUserID ?? "-"):\($0.replyToMessageID ?? "-")" })
        XCTAssertEqual(legacy.count, 1, "прежняя формула совмещала все шесть строк")
    }

    /// Сообщение, закрывшее живой ход, занимает строку хода: пока ход
    /// доигрывает ответ, сообщение скрыто, и при его появлении строка не
    /// пересоздаётся (иначе рвётся высота и прыгает прокрутка).
    func testMessageCompletingTurnTakesTurnRow() {
        XCTAssertEqual(RoleChatRowID.message("m1", completedTurn: "role:2026-10-21T13:19:39Z"),
                       RoleChatRowID.turn("role:2026-10-21T13:19:39Z"))
        XCTAssertEqual(RoleChatRowID.message("m1", completedTurn: nil),
                       RoleChatRowID.message("m1"))
        XCTAssertNotEqual(RoleChatRowID.message("m1"), RoleChatRowID.message("m2"))
    }

    /// Новое сообщение встаёт на своё место по серверному порядку
    /// (`sequence` — rowid), а не в конец и не с полной пересортировкой ленты.
    func testInsertingPlacesMessageByServerSequence() throws {
        let messages = try decode([RoleChatMessage].self, #"[{"id":"a","text":"1","created_at":"2026-10-21 13:00:00","is_session_marker":false,"sequence":1},{"id":"c","text":"3","created_at":"2026-10-21 13:00:02","is_session_marker":false,"sequence":3}]"#)
        let middle = try decode(RoleChatMessage.self, #"{"id":"b","text":"2","created_at":"2026-10-21 13:00:01","is_session_marker":false,"sequence":2}"#)
        let inserted = RoleChatMessageOrder.inserting(middle, into: messages)
        XCTAssertEqual(inserted.map(\.id), ["a", "b", "c"])
    }

    /// Известное сообщение заменяется на месте — порядок не трогаем.
    func testInsertingReplacesKnownMessageInPlace() throws {
        let messages = try decode([RoleChatMessage].self, #"[{"id":"a","text":"старое","created_at":"2026-10-21 13:00:00","is_session_marker":false,"sequence":1},{"id":"b","text":"2","created_at":"2026-10-21 13:00:01","is_session_marker":false,"sequence":2}]"#)
        let updated = try decode(RoleChatMessage.self, #"{"id":"a","text":"новое","created_at":"2026-10-21 13:00:00","is_session_marker":false,"sequence":1}"#)
        let result = RoleChatMessageOrder.inserting(updated, into: messages)
        XCTAssertEqual(result.map(\.id), ["a", "b"])
        XCTAssertEqual(result.first?.text, "новое")
    }

    /// Сообщения с одинаковой секундой сохраняют порядок поступления.
    func testInsertingKeepsEqualTimestampsInArrivalOrder() throws {
        let messages = try decode([RoleChatMessage].self, #"[{"id":"a","text":"1","created_at":"2026-10-21 13:00:00","is_session_marker":false},{"id":"b","text":"2","created_at":"2026-10-21 13:00:00","is_session_marker":false}]"#)
        let next = try decode(RoleChatMessage.self, #"{"id":"c","text":"3","created_at":"2026-10-21 13:00:00","is_session_marker":false}"#)
        let result = RoleChatMessageOrder.inserting(next, into: messages)
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
    }
}
