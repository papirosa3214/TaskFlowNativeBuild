import Foundation

struct OwnerCommandResult: Codable, Sendable {
    let outcome: String
    let exitCode: Int?
    let stdout: String
    let stderr: String
    let durationMs: Double
    let requestId: String
    let error: String?
}
extension APIClient {
    func runOwnerCommand(_ command: String) async throws -> OwnerCommandResult {
        struct Body: Encodable { let action = "chat.bash"; let command: String; let confirm = true }
        return try await request(.post, "/owner-command/run", body: Body(command: command), timeout: 45,
                                 acceptedErrorStatuses: [500, 504])
    }
}
