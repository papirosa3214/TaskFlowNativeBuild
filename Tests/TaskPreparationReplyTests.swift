import XCTest
@testable import TaskFlow

final class TaskPreparationReplyTests: XCTestCase {
    func testStructureQuestionProvidesAllThreeChoices() {
        let choices = TaskPreparationReply.choices(for: "Подготовить дочерние карточки, план по ролям или одну карточку с подшагами?")
        XCTAssertEqual(choices.map(\.id), ["children", "roles", "steps"])
        XCTAssertTrue(TaskPreparationReply.choices(for: "Какой журнал требуется?").isEmpty)
    }
    func testReplyPreservesDescriptionAndQuestion() {
        let description = TaskPreparationReply.description(original: "Исходная постановка", question: "Как подготовить?", answer: " По ролям ")
        XCTAssertTrue(description.hasPrefix("Исходная постановка\n\n"))
        XCTAssertTrue(description.contains("Вопрос: Как подготовить?"))
        XCTAssertTrue(description.hasSuffix("Ответ владельца: По ролям"))
    }
    func testEmptyAnswerDoesNotMakeRequests() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplyURLProtocol.self]
        ReplyURLProtocol.requests = 0
        do { try await APIClient(session: URLSession(configuration: configuration)).answerTaskPreparation(taskId: "task", preparationID: 1, inputVersion: 1, question: "Q", answer: " ")
            XCTFail("Empty answer accepted")
        } catch { XCTAssertEqual(ReplyURLProtocol.requests, 0) }
    }
    func testStaleQuestionCannotOverwriteDescription() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplyURLProtocol.self]
        ReplyURLProtocol.requests = 0
        do { try await APIClient(session: URLSession(configuration: configuration)).answerTaskPreparation(taskId: "task", preparationID: 1, inputVersion: 1, question: "Q", answer: "A")
            XCTFail("Stale answer accepted")
        } catch {
            XCTAssertEqual(ReplyURLProtocol.requests, 1)
            guard case APIError.server(let code, _) = error else { return XCTFail("Wrong error") }
            XCTAssertEqual(code, 409)
        }
    }
}
private final class ReplyURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let body = Data(#"{"preparation":{"id":2,"input_version":2,"status":"needs_clarification","result":{"question":"Changed"}}}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
