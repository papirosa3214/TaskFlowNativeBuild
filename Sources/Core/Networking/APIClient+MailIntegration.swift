import Foundation

extension APIClient {
    func mailAccounts() async throws -> MailAccountList {
        try await request(.get, "/integrations/composio/gmail/accounts")
    }

    /// Ссылка авторизации нового адреса; подпись — адрес, который вписал владелец.
    func addMailAccount(alias: String) async throws -> ComposioAuthorization {
        let body: [String: JSONValue] = alias.isEmpty ? [:] : ["alias": .string(alias)]
        return try await request(.post, "/integrations/composio/gmail/accounts", body: body)
    }

    func deleteMailAccount(id: String) async throws {
        try await requestVoid(.delete, "/integrations/composio/gmail/accounts/\(Self.pathPart(id))")
    }

    func mailTrustedSenders() async throws -> MailTrustedList {
        try await request(.get, "/integrations/mail/trusted")
    }

    func addMailTrustedSender(address: String) async throws -> MailTrustedList {
        let body: [String: JSONValue] = ["address": .string(address)]
        return try await request(.post, "/integrations/mail/trusted", body: body)
    }

    func deleteMailTrustedSender(address: String) async throws -> MailTrustedList {
        try await request(.delete, "/integrations/mail/trusted/\(Self.pathPart(address))")
    }

    private static func pathPart(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
