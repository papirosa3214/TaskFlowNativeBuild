import Foundation

private struct RoleChatsEnvelope: Decodable { let chats: [RoleChat] }
private struct RoleChatEnvelope: Decodable { let chat: RoleChat }
private struct RoleChatMessagesEnvelope: Decodable { let messages: [RoleChatMessage] }
private struct RoleChatMessageEnvelope: Decodable { let message: RoleChatMessage }

private struct CreateRoleChatBody: Encodable {
    let title: String?
    let kind: String
    let member_ids: [String]
}

public extension APIClient {
    func roleChats() async throws -> [RoleChat] {
        let response: RoleChatsEnvelope = try await request(.get, "/chats")
        return response.chats
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

    func roleChat(id: String) async throws -> RoleChat {
        let response: RoleChatEnvelope = try await request(.get, "/chats/\(id)")
        return response.chat
    }

    func roleChatMessages(id: String) async throws -> [RoleChatMessage] {
        let response: RoleChatMessagesEnvelope = try await request(.get, "/chats/\(id)/messages")
        return response.messages
    }

    func sendRoleChatMessage(chatID: String, text: String, attachmentIDs: [String] = []) async throws -> RoleChatMessage {
        struct Body: Encodable { let text: String; let attachment_ids: [String] }
        let response: RoleChatMessageEnvelope = try await request(
            .post, "/chats/\(chatID)/messages", body: Body(text: text, attachment_ids: attachmentIDs)
        )
        return response.message
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
}
