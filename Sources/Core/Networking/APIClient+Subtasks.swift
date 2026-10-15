import Foundation

/// Подзадачи и комментарии — spec/API.md §5.3.
public extension APIClient {

    func subtasks(taskId: String) async throws -> [ApiSubtask] {
        try await request(.get, "/tasks/\(taskId)/subtasks")
    }

    /// `afterId` — вставить сразу после этой подзадачи вместо конца списка;
    /// сервер сдвигает позиции остальных транзакционно (spec §5.3).
    func createSubtask(taskId: String, title: String, afterId: String? = nil) async throws -> ApiSubtask {
        var body: [String: JSONValue] = ["title": .string(title)]
        if let afterId { body["after_id"] = .string(afterId) }
        return try await request(.post, "/tasks/\(taskId)/subtasks", body: body)
    }

    /// `result` — до 400 символов (`RESULT_MAX`, spec §7). Партиальное тело —
    /// `[String: JSONValue]`, как и у задачи (см. `patchTask`).
    func patchSubtask(id: String, fields: [String: JSONValue]) async throws -> ApiSubtask {
        try await request(.patch, "/subtasks/\(id)", body: fields)
    }

    /// Своя дорожка состояния, ОТДЕЛЬНАЯ от `PATCH /subtasks/:id` — трекинг
    /// агентской работы конкретно над подзадачей (spec §5.3).
    func setSubtaskWork(id: String, fields: [String: JSONValue]) async throws -> ApiSubtask {
        try await request(.post, "/subtasks/\(id)/work", body: fields)
    }

    func deleteSubtask(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/subtasks/\(id)")
    }

    func comments(taskId: String) async throws -> [ApiComment] {
        try await request(.get, "/tasks/\(taskId)/comments")
    }

    /// Прикрепление ранее загруженных вложений — сначала `uploadRaw`
    /// (`APIClient+Attachments`), затем их id сюда.
    func createComment(taskId: String, text: String, attachmentIds: [String] = []) async throws -> ApiComment {
        var body: [String: JSONValue] = ["text": .string(text)]
        if !attachmentIds.isEmpty { body["attachment_ids"] = .strings(attachmentIds) }
        return try await request(.post, "/tasks/\(taskId)/comments", body: body)
    }

    /// Правка 9: выбрать машину выполнения шага. nil — вернуть на сервер.
    /// Отдельный маршрут, а не PATCH: те же правила доступа и запрет после
    /// старта шага, что и у выбора модели (см. owner-controls.ts).
    func setSubtaskHost(id: String, hostId: String?) async throws {
        let body: [String: JSONValue] = ["host_id": hostId.map { .string($0) } ?? .null]
        let _: SubtaskHostResponse = try await request(.put, "/subtasks/\(id)/host", body: body)
    }
}

/// Ответ `PUT /subtasks/:id/host`. Хотим ровно эти поля — лишние сервер может
/// добавить, а лишние у нас сломали бы декодирование.
public struct SubtaskHostResponse: Decodable, Sendable {
    public let ok: Bool
    public let subtaskId: String?
    public let hostId: String?
    enum CodingKeys: String, CodingKey {
        case ok
        case subtaskId = "subtask_id"
        case hostId = "host_id"
    }
}
