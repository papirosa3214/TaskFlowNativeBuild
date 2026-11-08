import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Разбор ссылки привязки телефона по QR.
///
/// Зачем это вообще: домашний вход без пароля (`TASKFLOW_LAN_NO_AUTH`)
/// выключен 08.11.2026 — сервер больше не отдаёт сессию владельца по одному
/// лишь адресу из домашней сети (`/auth/lan` отвечает 404). Телефон ходит
/// долгоживущим токеном устройства из связки ключей, но если токен пропал
/// (переустановка приложения, выход, ответ 401 и очистка Keychain), войти
/// нечем: пароль владельца набирать руками — не то, чего он хотел.
///
/// Теперь сервер печатает одноразовый код (`npx tsx scripts/pairing-code.ts`
/// или `POST /api/pairing/code`) и приложение меняет его на токен устройства
/// через `POST /api/pairing/exchange`. Ссылка внутри QR:
///
///     taskflow://pair?v=1&code=<32 hex>&host=<адрес ретранслятора>
///
/// `host` дома пустой и на вход не влияет: приложение работает по своему
/// встроенному адресу сервера, поле нужно внешнему доступу.
///
/// Тип держится отдельно от сети и UI намеренно: разбор — чистая функция, его
/// проверяет `Tools/test_pairing_link.py` без симулятора.
public enum PairingLink {
    /// Разобранная ссылка: сам код и предложенный адрес сервера.
    public struct Code: Equatable, Sendable {
        public let code: String
        public let host: String

        public init(code: String, host: String) {
            self.code = code
            self.host = host
        }
    }

    /// Схема зарегистрирована в `project.yml` (`CFBundleURLSchemes`), её же
    /// разбирает `RootView.onOpenURL` вместе с `taskflow://voice`.
    public static let scheme = "taskflow"
    /// Путь ссылки привязки. `voice` — голосовой режим, чужой путь здесь
    /// значит «это не про привязку».
    public static let path = "pair"
    /// 128 бит энтропии = 32 hex-символа (`CODE_BYTES = 16` на сервере).
    public static let codeLength = 32

    /// Разбор ссылки из QR. `nil` — ссылка не про привязку или код битый.
    public static func code(in url: URL) -> Code? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == path
        else { return nil }

        let query = queryItems(of: url)
        // Версия формата — часть адреса, а не украшение: если сервер начнёт
        // присылать `v=2` с другим набором полей, лучше не привязаться, чем
        // привязаться неправильно.
        if let version = query["v"], version != "1" { return nil }
        guard let raw = query["code"], let code = validated(raw) else { return nil }

        return Code(code: code, host: (query["host"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Код из ручного ввода или из ссылки, вставленной текстом.
    ///
    /// Терпимо к тому, что человек реально копирует: регистр букв, пробелы и
    /// переносы строк по краям и внутри, дефисы-разделители, а также саму
    /// ссылку `taskflow://pair?…` целиком (её видно под QR-кодом).
    public static func normalizedCode(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://"), let url = URL(string: trimmed), let parsed = code(in: url) {
            return parsed.code
        }
        return validated(trimmed)
    }

    /// Имя телефона для записи устройства в реестре сервера («iPhone Максима»).
    /// На macOS (проверка логики) UIKit нет — там имя не нужно.
    public static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }

    // MARK: - Внутреннее

    /// 32 hex в любом регистре; пробелы и дефисы считаются разделителями.
    private static func validated(_ value: String) -> String? {
        let compact = value.lowercased().filter { !$0.isWhitespace && $0 != "-" }
        guard compact.count == codeLength, compact.allSatisfy(\.isHexDigit) else { return nil }
        return compact
    }

    private static func queryItems(of url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(
            items.map { ($0.name.lowercased(), $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
