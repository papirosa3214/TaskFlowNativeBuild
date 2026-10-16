import XCTest
@testable import TaskFlow

final class JevSettingsTests: XCTestCase {
    func testScenarioPatchDoesNotOverwriteConnectionOrOtherScenarios() throws {
        let data = try JSONEncoder().encode(JevSettingsPatch(skillsEnabled: false))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["skillsEnabled"])
        XCTAssertEqual(object["skillsEnabled"] as? Bool, false)
    }

    func testConnectionPatchOmitsUnchangedKey() throws {
        let data = try JSONEncoder().encode(JevSettingsPatch(baseUrl: "https://example.com", model: "jev", timeoutMs: 3000))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["apiKey"])
        XCTAssertNil(object["skillsEnabled"])
    }

    func testConnectionResultDecodesBothServerOutcomes() throws {
        let success = try JSONDecoder().decode(JevConnectionResult.self, from: Data(#"{"ok":true,"models":["jev"],"ms":42}"#.utf8))
        XCTAssertTrue(success.ok)
        XCTAssertTrue(success.message.contains("42 мс"))
        let failure = try JSONDecoder().decode(JevConnectionResult.self, from: Data(#"{"ok":false,"error":"Ключ не задан"}"#.utf8))
        XCTAssertFalse(failure.ok)
        XCTAssertTrue(failure.message.contains("Ключ не задан"))
    }
}
