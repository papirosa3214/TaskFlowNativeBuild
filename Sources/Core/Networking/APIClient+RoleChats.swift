import Foundation

private struct RoleChatsEnvelope: Decodable { let chats: [RoleChat] }
private struct RoleChatEnvelope: Decodable { let chat: RoleChat }
private struct RoleChatMessagesEnvelope: Decodable { let messages: [RoleChatMessage] }
private struct RoleChatMessageEnvelope: Decodable { let message: RoleChatMessage }
private struct RoleChatLiveEnvelope: Decodable { let turns: [RoleChatLiveTurn] }

private struct RoleChatChecklistEnvelope: Decodable { let checklist_state: [ChecklistItemState] }

private struct CreateRoleChatBody: Encodable {
    let title: String?
    let kind: String
    let member_ids: [String]
}

public extension APIClient {
    func projectChat(projectID: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(.post, "/projects/\(projectID)/chat", body: [String: String]())
        return response.chat
    }
    func taskTopic(taskID: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(.post, "/tasks/\(taskID)/topic", body: [String: String]())
        return response.chat
    }
    func chatTopics(chatID: String, includeClosed: Bool = false) async throws -> [RoleChat] {
        let query = includeClosed ? [URLQueryItem(name: "include_closed", value: "1")] : []
        let response: RoleChatsEnvelope = try await request(.get, "/chats/\(chatID)/topics", query: query)
        return response.chats
    }

    func roleChats(includeClosed: Bool = false) async throws -> [RoleChat] {
        let query = includeClosed ? [URLQueryItem(name: "include_closed", value: "1")] : []
        let response: RoleChatsEnvelope = try await request(.get, "/chats", query: query)
        return response.chats
    }

    /// Постоянная личная комната роли — `POST /api/chats/with-role`; для
    /// внешнего агента создаёт её по просьбе владельца.
    func personalRoom(roleID: String) async throws -> RoleChat {
        struct Body: Encodable { let role_id: String }
        let response: RoleChatEnvelope = try await request(.post, "/chats/with-role", body: Body(role_id: roleID))
        return response.chat
    }

    /// Панель «Комнаты» — `GET /api/chats/rooms` (21.10.2026).
    func chatRooms() async throws -> ChatRoomsSnapshot {
        try await request(.get, "/chats/rooms")
    }

    /// Закрыть или вернуть сессию; постоянные комнаты сервер не закрывает.
    func closeRoleChat(id: String, closed: Bool) async throws -> RoleChat {
        struct Body: Encodable { let closed: Bool }
        let response: RoleChatEnvelope = try await request(.post, "/chats/\(id)/close", body: Body(closed: closed))
        return response.chat
    }

    func createRoleChat(title: String?, memberIDs: [String]) async throws -> RoleChat {
        let body = CreateRoleChatBody(
            title: title,
            kind: memberIDs.count == 1 ? "direct" : "group",
            member_ids: memberIDs
        )
        let response: RoleChatEnvelope = try await request(.post, "/chats", body: body)
        return response.chat
    }

    /// Ветка от сообщения: новый чат с теми же участниками и своей сессией роли.
    func createChatBranch(chatID: String, messageID: String) async throws -> RoleChat {
        struct Body: Encodable { let message_id: String }
        let response: RoleChatEnvelope = try await request(.post, "/chats/\(chatID)/branch", body: Body(message_id: messageID))
        return response.chat
    }

    func setChatExecutionMode(chatID: String, mode: ChatExecutionMode) async throws -> RoleChat {
        struct Body: Encodable { let execution_mode: ChatExecutionMode }
        let response: RoleChatEnvelope = try await request(.post, "/chats/\(chatID)/execution-mode", body: Body(execution_mode: mode))
        return response.chat
    }

    func roleChat(id: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(.get, "/chats/\(id)")
        return response.chat
    }

    func roleChatMessages(id: String) async throws -> [RoleChatMessage] {
        let response: RoleChatMessagesEnvelope = try await request(.get, "/chats/\(id)/messages")
        return response.messages
    }

    /// Идущие сейчас ходы ролей в чате — снимок для открывшего чат посреди
    /// ответа или после переподключения; дальше обновления идут `chats:live`.
    func reactToRoleChatMessage(chatID: String, messageID: String, emoji: String?) async throws -> RoleChatMessage {
        struct Body: Encodable {
            let emoji: String?
            enum CodingKeys: String, CodingKey { case emoji }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let emoji { try container.encode(emoji, forKey: .emoji) }
                else { try container.encodeNil(forKey: .emoji) }
            }
        }
        let response: RoleChatMessageEnvelope = try await request(.post, "/chats/\(chatID)/messages/\(messageID)/reaction", body: Body(emoji: emoji))
        return response.message
    }

    /// Отметка пункта checklist-виджета — один POST, ровно как у реакции
    /// (карточка 21842242). Сервер проверяет, что такой пункт есть в тексте
    /// сообщения, и отдаёт состояние всего сообщения: перерисовывать по
    /// ответу, отдельный GET не нужен.
    func setRoleChatChecklistItem(chatID: String, messageID: String, item: ChecklistItemState) async throws -> [ChecklistItemState] {
        struct Body: Encodable {
            let widget_key: String
            let item_key: String
            let done: Bool
        }
        let response: RoleChatChecklistEnvelope = try await request(
            .post,
            "/chats/\(chatID)/messages/\(messageID)/checklist",
            body: Body(widget_key: item.widgetKey, item_key: item.itemKey, done: item.done)
        )
        return response.checklist_state
    }

    func roleChatLive(id: String) async throws -> [RoleChatLiveTurn] {
        let response: RoleChatLiveEnvelope = try await request(.get, "/chats/\(id)/live")
        return response.turns
    }

    /// `recipientSubtaskID` — шаг плана, которому адресовано сообщение: сервер
    /// доставляет его роли этого шага, а не всем участникам чата.
    func sendRoleChatMessage(chatID: String, text: String, attachmentIDs: [String] = [], mode: RoleChatWorkMode = .work, executionMode: ChatExecutionMode? = nil,
                             model: String? = nil, recipientSubtaskID: String? = nil) async throws -> RoleChatMessage {
        struct Body: Encodable { let text: String; let attachment_ids: [String]; let work_mode: RoleChatWorkMode; let execution_mode: ChatExecutionMode?; let model: String?; let recipient_subtask_id: String? }
        let response: RoleChatMessageEnvelope = try await request(
            .post, "/chats/\(chatID)/messages",
            body: Body(text: text, attachment_ids: attachmentIDs, work_mode: mode, execution_mode: executionMode, model: model, recipient_subtask_id: recipientSubtaskID)
        )
        return response.message
    }

    /// Новая сессия без удаления истории (владелец 25.09.2026, docs/ПЛАН
    /// Супер Помощник владельца/): сбрасывает память роли в этом чате, история
    /// остаётся — сервер сам кладёт видимую метку-разделитель.
    func newRoleChatSession(chatID: String, roleID: String) async throws -> RoleChatMessage {
        struct Body: Encodable { let role_id: String }
        let response: RoleChatMessageEnvelope = try await request(
            .post, "/chats/\(chatID)/new-session", body: Body(role_id: roleID)
        )
        return response.message
    }

    /// «Сжать» (владелец 20.10.2026): сжать сессию роли в этом чате. Лента
    /// не меняется; роль продолжит ту же сессию, только короче.
    func compactRoleChatSession(chatID: String, roleID: String) async throws {
        struct Body: Encodable { let role_id: String }
        struct Result: Decodable { let ok: Bool }
        let _: Result = try await request(.post, "/chats/\(chatID)/compact", body: Body(role_id: roleID))
    }

    /// Остановить идущий ход роли (или всех ролей, если `roleID == nil`).
    /// Написанное ролью до остановки сервер кладёт в чат обычным ответом.
    @discardableResult
    func stopRoleChat(chatID: String, roleID: String? = nil) async throws -> Int {
        let body: [String: JSONValue] = roleID.map { ["role_id": .string($0)] } ?? [:]
        struct Result: Decodable { let stopped: Int }
        let response: Result = try await request(.post, "/chats/\(chatID)/stop", body: body)
        return response.stopped
    }

    func stopRoleCoordination(chatID: String, messageID: String) async throws {
        struct Result: Decodable { let stopped: Int }
        let _: Result = try await request(.post, "/chats/\(chatID)/coordination/\(messageID)/stop", body: [String: String]())
    }

    /// Сервер использует тот же raw-upload, что `/chat/attachments`.
    func uploadRoleChatAttachment(fileName: String, data: Data, mime: String) async throws -> ApiChatAttachment {
        struct Envelope: Decodable { let attachment: ApiChatAttachment }
        let response: Envelope = try await uploadRaw(
            path: "/chats/attachments",
            query: [URLQueryItem(name: "name", value: fileName)],
            data: data,
            mime: mime
        )
        return response.attachment
    }

    func addRoleChatMember(chatID: String, memberID: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(
            .post, "/chats/\(chatID)/members", body: ["member_id": memberID]
        )
        return response.chat
    }

    func removeRoleChatMember(chatID: String, memberID: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(
            .delete, "/chats/\(chatID)/members/\(memberID)"
        )
        return response.chat
    }

    /// Отметить чат прочитанным (участник). По этой отметке список чатов
    /// считает бейдж непрочитанных (миграция 055); зовётся при открытии
    /// комнаты и когда в открытом чате появилось чужое сообщение.
    func markRoleChatRead(id: String) async throws {
        try await requestVoid(.post, "/chats/\(id)/read")
    }

    /// Удалить сообщения чата. `ids` — выборка из режима выбора в комнате;
    /// пустой список означает «очистить чат целиком» и разрешён только
    /// создателю (владелец 21.09.2026: «либо удалить все, либо выбрать
    /// отдельные сообщения и потом удалить их»).
    @discardableResult
    func deleteRoleChatMessages(chatID: String, ids: [String] = []) async throws -> Int {
        var query: [URLQueryItem] = []
        if !ids.isEmpty {
            query.append(URLQueryItem(name: "ids", value: ids.joined(separator: ",")))
        }
        struct Result: Decodable { let deleted: Int }
        let response: Result = try await request(.delete, "/chats/\(chatID)/messages", query: query)
        return response.deleted
    }

    /// Удалить чат целиком (создатель). Сообщения уходят каскадом.
    func deleteRoleChat(id: String) async throws {
        try await requestVoid(.delete, "/chats/\(id)")
    }

    /// Переименовать чат (создатель). Пустая строка снимает название — тогда
    /// список и шапка показывают состав участников.
    func renameRoleChat(id: String, title: String) async throws -> RoleChat {
        let body: [String: JSONValue] = ["title": .string(title)]
        let response: RoleChatEnvelope = try await request(.patch, "/chats/\(id)", body: body)
        return response.chat
    }

    /// Привязать чат к задаче или отвязать (`nil`). Только создатель чата.
    /// Привязанный чат показывается в ленте задачи, а его сообщения начинают
    /// наследовать её — сервер переносит и уже написанные.
    ///
    /// Тело собирается вручную, а не `Encodable` с опционалом: синтезированный
    /// энкодер ПРОПУСКАЕТ `nil`, и сервер не отличил бы «отвязать» от «поле не
    /// пришло». Здесь `task_id: null` уходит явно.
    func bindRoleChatToTask(id: String, taskID: String?) async throws -> RoleChat {
        let body: [String: JSONValue] = ["task_id": taskID.map { .string($0) } ?? .null]
        let response: RoleChatEnvelope = try await request(.patch, "/chats/\(id)", body: body)
        return response.chat
    }
}

extension APIClient {
    func chatComposerControls(chatID: String, roleID: String) async throws -> ChatComposerControls {
        try await request(.get, "/chats/\(chatID)/controls", query: [URLQueryItem(name: "role_id", value: roleID)])
    }
}

private struct RoleChatDiscussionEnvelope: Decodable { let discussion: RoleChatDiscussion }
private struct RoleChatDiscussionsEnvelope: Decodable { let discussions: [RoleChatDiscussion] }

public extension APIClient {
    // Обсуждение работающей карточки (сервер: миграция 175_task_discussions,
    // карточка 252c400e, этапы 3–4). Обсуждение — отдельная сущность: свой
    // жизненный цикл, свой итог и своё обязательство для исполнителя.

    /// Открыть обсуждение карточки: `POST /api/tasks/:taskId/discussions`.
    /// Открывает владелец карточки.
    func createTaskDiscussion(taskID: String, subtaskID: String, role: String,
                              title: String? = nil) async throws -> RoleChatDiscussion {
        struct Body: Encodable {
            let subtask_id: String
            let role: String
            let title: String?
        }
        let response: RoleChatDiscussionEnvelope = try await request(
            .post, "/tasks/\(taskID)/discussions",
            body: Body(subtask_id: subtaskID, role: role, title: title))
        return response.discussion
    }

    /// Обсуждения карточки: `GET /api/tasks/:taskId/discussions`.
    func taskDiscussions(taskID: String) async throws -> [RoleChatDiscussion] {
        let response: RoleChatDiscussionsEnvelope = try await request(.get, "/tasks/\(taskID)/discussions")
        return response.discussions
    }

    /// Состояние обсуждения: `GET /api/discussions/:id`.
    func taskDiscussion(id: String) async throws -> RoleChatDiscussion {
        let response: RoleChatDiscussionEnvelope = try await request(.get, "/discussions/\(id)")
        return response.discussion
    }

    /// Закрыть обсуждение: сервер собирает итог и обязательство для
    /// исполнителя. Повторный вызов возвращает тот же итог, а не второй.
    func closeTaskDiscussion(id: String, recipientSubtaskID: String? = nil) async throws -> RoleChatDiscussion {
        let body: [String: JSONValue] = ["recipient_subtask_id": recipientSubtaskID.map { .string($0) } ?? .null]
        let response: RoleChatDiscussionEnvelope = try await request(.post, "/discussions/\(id)/close", body: body)
        return response.discussion
    }

    /// Принять обязательство: подтверждение, что итог доставлен исполнителю.
    func acceptTaskDiscussion(id: String) async throws -> RoleChatDiscussion {
        let response: RoleChatDiscussionEnvelope = try await request(.post, "/discussions/\(id)/accept", body: [String: JSONValue]())
        return response.discussion
    }
}
