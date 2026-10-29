import Foundation
import XCTest
@testable import TaskFlow

/// Адрес эндпоинта API (LOCK-ATTENTION-API-PATH-20261029).
///
/// Префикс `/api` добавляет клиент: в вызовах путь пишется без него. С
/// «/api/attention» получался `/api/api/attention` — сервер отвечал «не знаю
/// такого запроса».
final class AttentionApiPathTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.110:3001")!

    func testEndpointPathHasNoApiPrefix() {
        XCTAssertEqual(APIEndpoint.attention.list, "/attention")
        XCTAssertFalse(APIEndpoint.attention.list.contains("/api"))
    }

    func testUrlGetsExactlyOneApiPrefix() {
        let url = APIEndpoint.url(APIEndpoint.attention.list, base: base)
        XCTAssertEqual(url.absoluteString, "http://192.168.1.110:3001/api/attention")
        XCTAssertFalse(url.absoluteString.contains("/api/api"))
    }

    func testPathWithApiPrefixWouldDoubleIt() {
        // Страховка от возврата бага: клиент добавляет `/api` сам.
        let url = APIEndpoint.url("/api/attention", base: base)
        XCTAssertTrue(url.absoluteString.contains("/api/api"))
    }
}
