import Foundation

/// Состояние панели над полем ввода (владелец 11.11.2026): отложенные
/// сообщения владельца и работающие роли-исполнители. Всё хранит сервер,
/// телефон только показывает (`GET /chats/{id}/composer-status`).
struct ChatComposerStatus: Decodable, Sendable, Equatable {
    struct Queued: Decodable, Sendable, Equatable, Identifiable {
        let messageID: String
        let text: String
        let createdAt: String?
        var id: String { messageID }

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
            case text
            case createdAt = "created_at"
        }
    }

    struct Running: Decodable, Sendable, Equatable, Identifiable {
        enum State: String, Decodable, Sendable { case working, waiting, done }

        let chatID: String
        let roleID: String?
        let name: String
        let title: String?
        let state: State
        var id: String { chatID + ":" + (roleID ?? name) }

        enum CodingKeys: String, CodingKey {
            case chatID = "chat_id"
            case roleID = "role_id"
            case name, title, state
        }

        /// Свой список работающих — у сессий (роли-субагенты, 13.11.2026).
        init(chatID: String, roleID: String?, name: String, title: String?, state: State) {
            self.chatID = chatID
            self.roleID = roleID
            self.name = name
            self.title = title
            self.state = state
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            chatID = try c.decode(String.self, forKey: .chatID)
            roleID = try c.decodeIfPresent(String.self, forKey: .roleID)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Роль"
            title = try c.decodeIfPresent(String.self, forKey: .title)
            // Неизвестное состояние — как «работает»: роль в списке, а не пропала.
            state = (try? c.decodeIfPresent(State.self, forKey: .state)) ?? .working
        }
    }

    var queued: [Queued] = []
    var running: [Running] = []

    static let empty = ChatComposerStatus()

    init(queued: [Queued] = [], running: [Running] = []) {
        self.queued = queued
        self.running = running
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        queued = try c.decodeIfPresent([Queued].self, forKey: .queued) ?? []
        running = try c.decodeIfPresent([Running].self, forKey: .running) ?? []
    }

    enum CodingKeys: String, CodingKey { case queued, running }

    /// Роли, у которых сейчас идёт работа или которые ждут (готовые не показываем).
    var activeRunning: [Running] { running.filter { $0.state != .done } }
}

extension APIClient {
    func chatComposerStatus(chatID: String) async throws -> ChatComposerStatus {
        try await request(.get, "/chats/\(chatID)/composer-status")
    }

    /// «Отправить сейчас»: сервер доставляет отложенное сообщение роли.
    func sendQueuedNow(chatID: String, messageID: String) async throws -> ChatComposerStatus {
        try await request(.post, "/chats/\(chatID)/queued/\(messageID)/send-now")
    }

    /// «Убрать»: отложенное сообщение удаляется, роли оно не уйдёт.
    func removeQueued(chatID: String, messageID: String) async throws -> ChatComposerStatus {
        try await request(.delete, "/chats/\(chatID)/queued/\(messageID)")
    }
}
