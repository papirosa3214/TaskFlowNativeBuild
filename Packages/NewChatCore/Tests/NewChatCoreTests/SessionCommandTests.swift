import XCTest
@testable import NewChatCore

final class SessionCommandTests: XCTestCase {
    private let encoder = JSONEncoder()

    func testPromptModesEncodeExactlyLikeServerContract() throws {
        let cases: [(SessionPromptMode, String)] = [
            (.prompt, "prompt"), (.steer, "steer"), (.followUp, "follow_up"),
        ]

        for (mode, wireValue) in cases {
            let request = PromptSessionRequest(requestId: "request-1", text: "hello", mode: mode)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: String])
            XCTAssertEqual(json, ["requestId": "request-1", "text": "hello", "mode": wireValue])
        }
    }

    func testBranchAndForkShareEntryCommandShape() throws {
        let command = SessionEntryCommandRequest(requestId: "request-2", entryId: "entry-7")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(command)) as? [String: String])

        XCTAssertEqual(json, ["requestId": "request-2", "entryId": "entry-7"])
    }

    func testTransportTimeoutRemainsUnknownInsteadOfFailed() {
        var state = SessionState(snapshot: nil)
        state.markCommandStarted(requestId: "request-3")

        state.markCommandTimedOut(requestId: "request-3")

        XCTAssertEqual(state.commandDelivery, .unknown(requestId: "request-3"))
    }

    func testSummaryDecodesForkAndChildParentLinks() throws {
        let data = #"""
        {"sessions":[
          {"id":"root","cwd":"/project","name":"Owner assistant"},
          {"id":"fork","cwd":"/project","parentSession":"/sessions/root.jsonl"},
          {"id":"child","cwd":"/project/sub","parentSession":"/sessions/root.jsonl"}
        ]}
        """#

        let response = try XCTUnwrap(SessionListResponse(json: try JSONValue.parse(data)))

        XCTAssertNil(response.sessions[0].parentSession)
        XCTAssertEqual(response.sessions[1].parentSession, "/sessions/root.jsonl")
        XCTAssertEqual(response.sessions[2].parentSession, "/sessions/root.jsonl")
    }

    func testSetSessionModelRequestEncodesProviderAndModel() throws {
        let request = SetSessionModelRequest(
            requestId: "r-1",
            provider: "anthropic",
            model: "claude-haiku-4-5"
        )
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String]

        XCTAssertEqual(object?["requestId"], "r-1")
        XCTAssertEqual(object?["provider"], "anthropic")
        XCTAssertEqual(object?["model"], "claude-haiku-4-5")
    }
}
