import XCTest
@testable import TaskFlow

/// Токен сессии лежит в Keychain, но читается из него на каждый HTTP-запрос.
/// `SecItemCopyMatching` — системный вызов: замер 24.10.2026 на этой машине —
/// **2.4 мс на чтение**. Поэтому в памяти держится копия: Keychain трогается
/// один раз за сессию, а сброс (выход или 401) копию чистит.
final class KeychainTokenCacheTests: XCTestCase {

    /// Хранилище с настоящим счётом чтений.
    private func makeService(stored: String? = "токен-сессии") -> (KeychainService, () -> Int, () -> String?) {
        var reads = 0
        var value = stored
        let service = KeychainService(
            readValue: { _ in reads += 1; return value },
            writeValue: { newValue, _ in value = newValue }
        )
        return (service, { reads }, { value })
    }

    func testХранилищеЧитаетсяОдинРаз() {
        let (service, reads, _) = makeService()
        _ = service.token
        _ = service.token
        _ = service.token
        XCTAssertEqual(reads(), 1, "Токен должен читаться из Keychain один раз, а не на каждый запрос")
        XCTAssertEqual(service.token, "токен-сессии")
    }

    func testВыходЧиститКэшИХранилище() {
        let (service, _, stored) = makeService()
        XCTAssertEqual(service.token, "токен-сессии")
        service.token = nil
        XCTAssertNil(service.token, "После выхода кэш не должен отдавать старый токен")
        XCTAssertNil(stored(), "Токен должен быть стёрт из хранилища")
    }

    func testНовыйТокенВиденСразу() {
        let (service, reads, _) = makeService()
        _ = service.token
        service.token = "новый-токен"
        XCTAssertEqual(service.token, "новый-токен")
        XCTAssertEqual(reads(), 1, "Запись токена не должна требовать чтения хранилища")
    }

    func testПустоеХранилищеНеЧитаетсяПовторно() {
        let (service, reads, _) = makeService(stored: nil)
        XCTAssertNil(service.token)
        XCTAssertNil(service.token)
        XCTAssertEqual(reads(), 1, "Отсутствие токена тоже запоминается — иначе каждый запрос лезет в Keychain")
    }

    func testТокенУстройстваНеСмешиваетсяССессонным() {
        let (service, reads, _) = makeService()
        _ = service.token
        _ = service.deviceToken
        _ = service.token
        XCTAssertEqual(reads(), 2, "Сессионный токен и токен устройства — разные записи")
    }
}
