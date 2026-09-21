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

/// Согласованный клиентский ответ этапа 4: сервер возвращает идентификатор
/// созданной карточки, чтобы сразу открыть её из чата.
public struct RoleChatDraftResult: Decodable, Sendable {
    public let taskID: String?
    public let task: TaskReference?
    public let draftID: String?
    public let status: String?

    public struct TaskReference: Decodable, Sendable { public let id: String }
    enum CodingKeys: String, CodingKey {
        case taskID = "task_id", task, status
        case draftID = "draft_id"
    }
    public var createdTaskID: String? { taskID ?? task?.id }
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

    func assembleRoleChatTask(chatID: String) async throws -> RoleChatDraftResult {
        try await request(.post, "/chats/\(chatID)/draft", body: [String: String]())
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
}
