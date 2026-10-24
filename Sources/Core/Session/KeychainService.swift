import Foundation
import Security

/// Хранилище токена сессии в Keychain — spec/API.md §2.2: «токен живёт 30 дней,
/// это секрет уровня пароля, UserDefaults не подходит». Один и тот же
/// заголовок `Authorization: Bearer <значение>` годится и для JWT, и для
/// api_token (сервер сам разбирает, что прислано) — поэтому хранится просто
/// как «текущий токен», без разделения на два вида.
///
/// Токен лежит ещё и в памяти: `SecItemCopyMatching` — системный вызов,
/// замер 24.10.2026 на этой машине — **2.4 мс на чтение**, а читается он на
/// каждый HTTP-запрос (и на каждое открытие сокета). В памяти он держится до
/// выхода/сброса, поэтому Keychain трогается один раз за сессию.
///
/// `@unchecked Sendable`: сама Keychain API синхронна и потокобезопасна на
/// уровне ОС; кэш под своим локом, изменяемого состояния экземпляра больше нет.
public final class KeychainService: @unchecked Sendable {
    public static let shared = KeychainService()

    private static let service = "com.maksim.taskflow.native"
    private let account = "session-token"
    /// Токен УСТРОЙСТВА лежит отдельной записью: по нему телефон заходит на
    /// сокет команд `device_op`, и отзывается он отдельно от сессии.
    private let deviceAccount = "device-token"

    /// Чтение и запись в хранилище — подменяются в тестах (в тестовом наборе
    /// Keychain без entitlement недоступен).
    private let readValue: (String) -> String?
    private let writeValue: (String?, String) -> Void

    init(readValue: ((String) -> String?)? = nil, writeValue: ((String?, String) -> Void)? = nil) {
        self.readValue = readValue ?? KeychainService.readKeychain
        self.writeValue = writeValue ?? KeychainService.writeKeychain
    }

    /// Кэш значения в памяти. `hasCached` отличает «не читали ещё» от
    /// «прочитали, значения нет» — токена может не быть вовсе.
    private let cacheLock = NSLock()
    private var cachedToken: String?
    private var hasCachedToken = false

    /// Текущий токен, если пользователь входил и не выходил. `nil` — нет
    /// сессии, показывать экран входа.
    public var token: String? {
        get {
            cacheLock.lock()
            if hasCachedToken {
                let value = cachedToken
                cacheLock.unlock()
                return value
            }
            cacheLock.unlock()

            let value = readValue(account)

            cacheLock.lock()
            cachedToken = value
            hasCachedToken = true
            cacheLock.unlock()
            return value
        }
        set {
            writeValue(newValue, account)
            cacheLock.lock()
            cachedToken = newValue
            hasCachedToken = true
            cacheLock.unlock()
        }
    }

    /// Токен устройства — вход на сокет команд `device_op`. Отдельно от
    /// токена сессии: сессию перевыпускают при входе, устройство отзывает
    /// владелец на сервере.
    public var deviceToken: String? {
        get { readValue(deviceAccount) }
        set { writeValue(newValue, deviceAccount) }
    }

    private static func readKeychain(_ account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String?, _ account: String) {
        guard let value else {
            deleteKeychain(account)
            return
        }
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        // Сначала пробуем обновить существующую запись — SecItemAdd на уже
        // занятый account/service вернёт errSecDuplicateItem.
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func deleteKeychain(_ account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
