import Foundation
import XCTest
@testable import TaskFlow

@MainActor
final class ProjectCancellationTests: XCTestCase {
    func testCancellationIsSilentAndPreservesLoadedProjects() async {
        let store = makeStore()
        ProjectCancellationProtocol.failure = false
        await store.load()
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.projects.map(\.id), ["project-1"])
        ProjectCancellationProtocol.failure = true
        await store.load()
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.projects.map(\.id), ["project-1"])
    }
    func testRealServerErrorStillAppears() async {
        let store = makeStore()
        ProjectCancellationProtocol.failure = false
        ProjectCancellationProtocol.status = 500
        defer { ProjectCancellationProtocol.status = 200 }
        await store.load()
        XCTAssertNotNil(store.errorMessage)
    }
    private func makeStore() -> ProjectStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProjectCancellationProtocol.self]
        return ProjectStore(apiClient: APIClient(session: URLSession(configuration: configuration)))
    }
}
private final class ProjectCancellationProtocol: URLProtocol {
    static var failure = false
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.failure {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.status == 200 ? "[{\"id\":\"project-1\",\"name\":\"Проект\"}]" : "{\"error\":\"Сбой сервера\"}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
