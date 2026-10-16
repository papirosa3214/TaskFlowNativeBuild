import Foundation

struct JevSettings: Decodable, Sendable {
    let baseUrl: String
    let model: String
    let timeoutMs: Int
    let hasApiKey: Bool
    let planProfileEnabled: Bool
    let subtaskRoleEnabled: Bool
    let memoryRecallEnabled: Bool
    let memoryWriteEnabled: Bool
    let skillsEnabled: Bool
}

/// Only changed fields are sent. An empty key never deletes the saved key.
struct JevSettingsPatch: Encodable, Sendable {
    var baseUrl: String?
    var model: String?
    var timeoutMs: Int?
    var apiKey: String?
    var planProfileEnabled: Bool?
    var subtaskRoleEnabled: Bool?
    var memoryRecallEnabled: Bool?
    var memoryWriteEnabled: Bool?
    var skillsEnabled: Bool?
}

struct JevConnectionResult: Decodable, Sendable {
    let ok: Bool
    let models: [String]?
    let ms: Int?
    let error: String?

    var message: String {
        if !ok { return "Не подключилось: \(error ?? "Неизвестная ошибка")" }
        return "Подключено за \(ms ?? 0) мс. Модели: \(models?.joined(separator: ", ").nilIfEmpty ?? "—")"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension APIClient {
    func jevSettings() async throws -> JevSettings {
        try await request(.get, "/jev/settings")
    }
    func saveJevSettings(_ patch: JevSettingsPatch) async throws -> JevSettings {
        try await request(.put, "/jev/settings", body: patch)
    }
    func resetJevSettings() async throws -> JevSettings {
        try await request(.delete, "/jev/settings")
    }
    func testJevConnection() async throws -> JevConnectionResult {
        try await request(.post, "/jev/test", timeout: 65)
    }
}
