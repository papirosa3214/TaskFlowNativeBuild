import Foundation

public extension APIClient {
    func taskPreparation(taskId: String) async throws -> ApiTaskPreparation? {
        #if DEBUG
        if let mode = ProcessInfo.processInfo.environment["TASKFLOW_PREPARATION_PREVIEW"], ["executor", "structure"].contains(mode) {
            return try await PreparationPreview.shared.snapshot(mode: mode)
        }
        #endif
        struct Envelope: Decodable { let preparation: ApiTaskPreparation? }
        let value: Envelope = try await request(.get, "/tasks/\(taskId)/preparation")
        guard var preparation = value.preparation else { return nil }
        if preparation.status == "needs_clarification", preparation.question == nil {
            struct Clarification: Decodable { let clarification_question: String? }
            let card: Clarification = try await request(.get, "/tasks/\(taskId)")
            preparation.taskQuestion = card.clarification_question
        }
        return preparation
    }
    func retryTaskPreparation(taskId: String) async throws {
        struct Reply: Decodable { let queued: Bool }
        let _: Reply = try await request(.post, "/tasks/\(taskId)/preparation/retry")
    }
    func approveTaskStructure(taskId: String, inputVersion: Int) async throws {
        struct Body: Encodable { let input_version: Int }
        struct Reply: Decodable { let child_ids: [String] }
        let _: Reply = try await request(.post, "/tasks/\(taskId)/preparation/approve-structure", body: Body(input_version: inputVersion))
    }
}

/// Ответ сохраняется в постановке, которую читает автомат подготовки.
enum TaskPreparationReply {
    struct Choice: Identifiable {
        let id: String
        let title: String
        let answer: String
    }
    static func choices(for question: String, roles: [Choice] = []) -> [Choice] {
        let text = question.lowercased()
        if text.contains("исполнител") || text.contains("какую роль") || text.contains("кто выполн") {
            return roles
        }
        // Только вопрос, в котором перечислены эти три способа подготовки.
        guard text.contains("дочер"), text.contains("рол"),
              text.contains("подшаг") || text.contains("одн") || text.contains("подзадач") else { return [] }
        return [
            Choice(id: "children", title: "Дочерние карточки", answer: "Подготовить дочерние карточки по самостоятельным результатам работы."),
            Choice(id: "roles", title: "План совместной работы по ролям", answer: "Подготовить план совместной работы по ролям в рамках одной карточки."),
            Choice(id: "steps", title: "Одна карточка с подшагами", answer: "Оставить одну карточку с подшагами, без создания дочерних карточек.")
        ]
    }
    static func description(original: String?, question: String, answer: String) -> String {
        [original?.trimmingCharacters(in: .whitespacesAndNewlines),
         "Уточнение подготовки\nВопрос: \(question)\nОтвет владельца: \(answer.trimmingCharacters(in: .whitespacesAndNewlines))"]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

public extension APIClient {
    func answerTaskPreparation(taskId: String, preparationID: Int, inputVersion: Int, question: String, answer: String) async throws {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.server(status: 400, message: "Выберите ответ") }
        guard let current = try await taskPreparation(taskId: taskId),
              current.id == preparationID, current.inputVersion == inputVersion,
              current.question == question,
              current.status == "needs_clarification" || current.status == "structure_review" else {
            throw APIError.server(status: 409, message: "Вопрос подготовки изменился. Обновите окно и выберите ответ на новый вопрос.")
        }
        #if DEBUG
        if let mode = ProcessInfo.processInfo.environment["TASKFLOW_PREPARATION_PREVIEW"], ["executor", "structure"].contains(mode) {
            await PreparationPreview.shared.submit()
            return
        }
        #endif
        let task = try await self.task(id: taskId)
        _ = try await patchTask(id: taskId, fields: ["description": .string(TaskPreparationReply.description(original: task.description, question: question, answer: trimmed))])
    }
}

#if DEBUG
/// Подменяет только ответ подготовки для точного UI-теста; реальные карточки не меняет.
private actor PreparationPreview {
    static let shared = PreparationPreview()
    private var submitted = false
    func submit() { submitted = true }
    func snapshot(mode: String) throws -> ApiTaskPreparation {
        let question = mode == "executor"
            ? "Уточните исполнителя результата перед согласованием плана."
            : "Подготовить дочерние карточки, план по ролям или одну карточку с подшагами?"
        let payload: [String: Any] = ["id": 420, "input_version": 1,
            "status": submitted ? "queued" : "needs_clarification",
            "result": ["question": submitted ? NSNull() : question as Any]]
        return try JSONDecoder().decode(ApiTaskPreparation.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
#endif
