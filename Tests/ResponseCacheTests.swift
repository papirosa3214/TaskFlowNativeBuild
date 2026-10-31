import XCTest
@testable import TaskFlow

final class ResponseCacheTests: XCTestCase {
    private func makeCache() -> (ResponseCache, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ResponseCache(directory: dir), dir)
    }

    func testStoredResponseSurvivesNewInstance() {
        let (cache, dir) = makeCache()
        cache.store(Data("a".utf8), for: "/tasks?x=1")
        XCTAssertEqual(ResponseCache(directory: dir).data(for: "/tasks?x=1"), Data("a".utf8))
        XCTAssertNil(cache.data(for: "/tasks?x=2"))
    }

    func testRemoveAllClearsMemoryAndDisk() {
        let (cache, dir) = makeCache()
        cache.store(Data("a".utf8), for: "/notes")
        cache.removeAll()
        XCTAssertNil(cache.data(for: "/notes"))
        XCTAssertNil(ResponseCache(directory: dir).data(for: "/notes"))
    }

    func testKeyIgnoresQueryOrder() {
        XCTAssertEqual(
            ResponseCache.key(path: "/t", query: [URLQueryItem(name: "b", value: "2"), URLQueryItem(name: "a", value: "1")]),
            ResponseCache.key(path: "/t", query: [URLQueryItem(name: "a", value: "1"), URLQueryItem(name: "b", value: "2")])
        )
    }
}
