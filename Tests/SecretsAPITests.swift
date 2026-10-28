import XCTest
@testable import TaskFlow

final class SecretsAPITests: XCTestCase {
    func testDecodesListWithoutValues() throws {
        let json = #"{"secrets":[{"id":"openai","name":"OpenAI","origin":"https://api.openai.com/v1","header_name":"Authorization"}]}"#
        struct Envelope: Decodable { let secrets: [BrokerSecret] }
        let list = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).secrets
        XCTAssertEqual(list.first?.headerName, "Authorization")
        XCTAssertEqual(list.first?.displayOrigin, "api.openai.com/v1")
    }

    func testMakeIDFollowsServerRules() {
        XCTAssertEqual(BrokerSecret.makeID(from: "OpenAI"), "openai")
        XCTAssertEqual(BrokerSecret.makeID(from: "GitHub Token (личный)"), "github-token")
        XCTAssertEqual(BrokerSecret.makeID(from: "  api.exa.ai v2 "), "api.exa.ai-v2")
        XCTAssertTrue(BrokerSecret.makeID(from: "Ключ").hasPrefix("secret-"))
        XCTAssertLessThanOrEqual(BrokerSecret.makeID(from: String(repeating: "a", count: 100)).count, 64)
    }
}
