import Foundation

struct IntegrationResponsibility: Decodable, Sendable {
    struct Candidate: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let role: String
    }
    let mode: String
    let owner_id: String?
    let owner_title: String?
    let candidates: [Candidate]
    let valid: Bool
}

extension APIClient {
    func integrationResponsibility(taskID: String) async throws -> IntegrationResponsibility {
        try await request(.get, "/tasks/\(taskID)/integration-responsibility")
    }
    func setIntegrationResponsibility(taskID: String, mode: String, ownerID: String?) async throws -> IntegrationResponsibility {
        struct Body: Encodable { let mode: String; let owner_id: String? }
        return try await request(.patch, "/tasks/\(taskID)/integration-responsibility", body: Body(mode: mode, owner_id: ownerID))
    }
}
