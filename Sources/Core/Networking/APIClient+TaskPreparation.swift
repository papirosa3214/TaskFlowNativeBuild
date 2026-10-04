import Foundation

public extension APIClient {
    func taskPreparation(taskId: String) async throws -> ApiTaskPreparation? {
        struct Envelope: Decodable { let preparation: ApiTaskPreparation? }
        let value: Envelope = try await request(.get, "/tasks/\(taskId)/preparation")
        return value.preparation
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
