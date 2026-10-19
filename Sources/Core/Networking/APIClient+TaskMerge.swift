import Foundation

/// Перенос ветки роли в `main`: очередь целиком и откат уже слитого.
extension APIClient {
    /// Очередь автослияния (`GET /api/merges/queue`, только владелец).
    func mergeQueue() async throws -> ApiMergeQueue {
        try await request(.get, "/merges/queue")
    }

    /// Откатить слияние карточки коммитом-возвратом (`main` не переписывается).
    func rollBackMerge(taskID: String) async throws {
        try await requestVoid(.post, "/merges/roll-back", body: ["task_id": taskID])
    }
}
