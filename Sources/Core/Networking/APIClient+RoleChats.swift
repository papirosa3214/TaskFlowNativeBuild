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

    func sendRoleChatMessage(chatID: String, text: String) async throws -> RoleChatMessage {
        let response: RoleChatMessageEnvelope = try await request(
            .post, "/chats/\(chatID)/messages", body: ["text": text]
        )
        return response.message
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
}
