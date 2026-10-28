import Foundation

/// Ключ из хранилища секретов (Agent Secret Broker на .110). Значение в
/// списке не приходит — только по отдельному запросу `revealSecret`.
struct BrokerSecret: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let origin: String
    let headerName: String

    enum CodingKeys: String, CodingKey {
        case id, name, origin
        case headerName = "header_name"
    }

    /// `https://api.openai.com/v1` → `api.openai.com/v1` для строки списка.
    var displayOrigin: String {
        origin.replacingOccurrences(of: "https://", with: "")
    }

    /// Id для нового ключа из названия: латиница, цифры, `.`, `-`, `_`, до 64
    /// символов — те же правила, что у сервера (`routes/secrets.ts`).
    static func makeID(from name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        var id = ""
        for ch in name.lowercased() {
            if allowed.contains(ch) { id.append(ch) }
            else if !id.isEmpty, id.last != "-" { id.append("-") }
        }
        while let last = id.last, !last.isLetter && !last.isNumber { id.removeLast() }
        id = String(id.prefix(64))
        return id.isEmpty ? "secret-\(Int(Date().timeIntervalSince1970))" : id
    }
}

extension APIClient {
    func secrets() async throws -> [BrokerSecret] {
        struct Envelope: Decodable { let secrets: [BrokerSecret] }
        let result: Envelope = try await request(.get, "/secrets")
        return result.secrets
    }

    @discardableResult
    func saveSecret(id: String, name: String, origin: String, headerName: String, value: String) async throws -> BrokerSecret {
        struct Body: Encodable {
            let name: String
            let origin: String
            let header_name: String
            let value: String
        }
        return try await request(.put, "/secrets/\(id)", body: Body(name: name, origin: origin, header_name: headerName, value: value))
    }

    func revealSecret(id: String) async throws -> String {
        struct Revealed: Decodable { let value: String }
        let result: Revealed = try await request(.post, "/secrets/\(id)/reveal")
        return result.value
    }

    func deleteSecret(id: String) async throws {
        try await requestVoid(.delete, "/secrets/\(id)")
    }
}
