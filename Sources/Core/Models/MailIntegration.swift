import Foundation

/// Подключённый адрес почты владельца (аккаунт Gmail в Composio).
public struct MailAccount: Decodable, Identifiable, Sendable {
    public let id: String
    public let address: String?
    public let alias: String?
    public let status: String

    public var title: String { address ?? alias ?? "Без адреса" }
    public var connected: Bool { status == "ACTIVE" }
}

public struct MailAccountList: Decodable, Sendable {
    public let items: [MailAccount]
}

/// Отправитель из белого списка: его письма Секретарь читает напрямую.
public struct MailTrustedSender: Decodable, Identifiable, Sendable {
    public let address: String
    public var id: String { address }
}

public struct MailTrustedList: Decodable, Sendable {
    public let items: [MailTrustedSender]
}
