import Foundation

/// Живая активность агента по задаче — `server/src/routes/activity.ts`.
public extension APIClient {

    /// Чем агент занят прямо сейчас.
    ///
    /// Сам факт запроса — сигнал серверу «на карточку смотрят»: по нему он
    /// решает, звать ли локальную модель за пересказом (иначе она молотила бы
    /// над задачами, которых никто не открывал). Поэтому опрашивать нужно,
    /// пока карточка открыта, а не один раз при появлении.
    func taskActivity(taskId: String) async throws -> ApiTaskActivity {
        try await request(.get, "/tasks/\(taskId)/activity")
    }
}

public struct TaskLiveTurn: Decodable, Sendable, Equatable {
    public let taskID: String
    public let subtaskID: String?
    public let runID: String
    public let complete: Bool
    public let turn: RoleChatLiveTurn
    enum CodingKeys: String, CodingKey {
        case taskID = "task_id", subtaskID = "subtask_id", runID = "run_id"
        case complete, turn
    }
}
private struct TaskLiveEnvelope: Decodable { let turns: [TaskLiveTurn] }
public extension APIClient {
    func taskLiveTurns(taskID: String) async throws -> [TaskLiveTurn] {
        let response: TaskLiveEnvelope = try await request(.get, "/tasks/\(taskID)/live")
        return response.turns
    }
}
