import Foundation

/// Где клиент сессий берёт токен. В прототипе NewChatTF был свой Keychain;
/// в TaskFlow токен один на всё приложение — `KeychainService`.
protocol SessionTokenStoring: AnyObject, Sendable {
    var token: String? { get set }
}

/// Токен TaskFlow для клиента сессий: читает и пишет тот же `KeychainService`,
/// что и `SessionStore`, поэтому домашний вход обновляет токен для всех.
final class TaskFlowSessionToken: SessionTokenStoring, @unchecked Sendable {
    static let shared = TaskFlowSessionToken()

    var token: String? {
        get { KeychainService.shared.token }
        set { KeychainService.shared.token = newValue }
    }
}
