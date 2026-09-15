import Foundation

struct ThingsBridgeSyncResult: Decodable, Sendable {
    let projectsCreated: Int
    let imported: Int
    let exported: Int
    let updated: Int
    let skipped: Int
    let errors: Int

    enum CodingKeys: String, CodingKey {
        case projectsCreated = "projects_created"
        case imported, exported, updated, skipped, errors
    }
}

struct ThingsBridgeAPI: Sendable {
    static let shared = ThingsBridgeAPI()
    private let baseURL = URL(string: "http://192.168.1.128:8765")!

    func health() async throws -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return (try? JSONDecoder().decode([String: Bool].self, from: data)["ok"]) == true
    }

    func sync() async throws -> ThingsBridgeSyncResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ThingsBridgeError.unavailable
        }
        return try JSONDecoder().decode(ThingsBridgeSyncResult.self, from: data)
    }
}

enum ThingsBridgeError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Мост Things на MacBook недоступен" }
}
