import Foundation
import XCTest
@testable import TaskFlow

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testSendRefreshesLatestPageWithoutMovingHistoryCursor() async throws {
        let probe = ChatRequestProbe()
        ChatURLProtocol.handler = { request in
            try probe.response(for: request)
        }
        defer { ChatURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatURLProtocol.self]
        let viewModel = ChatViewModel(api: APIClient(session: URLSession(configuration: configuration)))

        await viewModel.loadHistory()
        viewModel.addressee = .all
        viewModel.draftText = "new"
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.map(\.id), ["old", "new"])
        XCTAssertEqual(viewModel.messages.filter { $0.id == "old" }.count, 1)

        await viewModel.loadHistory()
        let snapshot = probe.snapshot()
        XCTAssertEqual(snapshot.chatMethods, ["GET", "POST", "GET", "GET"])
        XCTAssertEqual(snapshot.getBeforeValues.count, 3)
        XCTAssertNil(snapshot.getBeforeValues[0])
        XCTAssertNil(snapshot.getBeforeValues[1])
        XCTAssertEqual(snapshot.getBeforeValues[2], "old")
    }
}

private final class ChatRequestProbe: @unchecked Sendable {
    struct Snapshot {
        let chatMethods: [String]
        let getBeforeValues: [String?]
    }

    private let lock = NSLock()
    private var chatMethods: [String] = []
    private var getBeforeValues: [String?] = []

    func response(for request: URLRequest) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let method = request.httpMethod ?? ""
        let path = request.url?.path

        if path == "/api/chat/typing" {
            return Data(#"{"печатает":true}"#.utf8)
        }

        chatMethods.append(method)

        if method == "POST" {
            return Data(#"{"id":"new","channel":"agents","text":"new"}"#.utf8)
        }

        let before = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "before" }?
            .value
        getBeforeValues.append(before)

        switch getBeforeValues.count {
        case 1:
            return Data(#"{"messages":[{"id":"old","channel":"agents","text":"old"}],"has_more":true}"#.utf8)
        case 2:
            return Data(#"{"messages":[{"id":"old","channel":"agents","text":"old"},{"id":"new","channel":"agents","text":"new"}],"has_more":true}"#.utf8)
        default:
            return Data(#"{"messages":[],"has_more":false}"#.utf8)
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(chatMethods: chatMethods, getBeforeValues: getBeforeValues)
    }
}

private final class ChatURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let data = try XCTUnwrap(Self.handler)(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
