import XCTest
@testable import TaskFlow

private final class CommandURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var lastBody: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let data = request.httpBody { Self.lastBody = data }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
            Self.lastBody = data
        }
        let body = Data(#"{"outcome":"timeout","stdout":"partial","stderr":"","durationMs":30000,"requestId":"test","exitCode":null}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class OwnerCommandTests: XCTestCase {
    func testTimeoutKeepsOutputAndConfirmedCommandBody() async throws {
        CommandURLProtocol.status = 504
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommandURLProtocol.self]
        let api = APIClient(session: URLSession(configuration: configuration))
        let result = try await api.runOwnerCommand("printf 'two words'")
        XCTAssertEqual(result.outcome, "timeout")
        XCTAssertEqual(result.stdout, "partial")
        let body = try XCTUnwrap(CommandURLProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "printf 'two words'")
        XCTAssertEqual(json["confirm"] as? Bool, true)
    }
    func testOnlyClosedBashBlocksParseAsExecutableCode() {
        let blocks = MarkdownParser.parse("```bash\nprintf 'ok'\n```")
        XCTAssertEqual(blocks.count, 1)
        if case .codeBlock(let language) = blocks[0].kind { XCTAssertEqual(language, "bash") }
        else { XCTFail("Expected bash") }
        XCTAssertFalse(MarkdownParser.parse("```bash\nprintf 'unfinished'").contains {
            if case .codeBlock = $0.kind { return true }; return false
        })
    }
}
