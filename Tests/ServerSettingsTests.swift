import XCTest
@testable import TaskFlow

final class ServerSettingsTests: XCTestCase {
    private func setting(kind: String = "duration_min") throws -> ServerSetting {
        try JSONDecoder().decode(ServerSetting.self, from: Data("""
        {"key":"silence","label":"Тишина","group":"тишина","kind":"\(kind)","default":10,"min":1,"max":120}
        """.utf8))
    }
    func testBoundsAndInvalidNumbers() throws {
        let s = try setting()
        XCTAssertEqual(try s.validatedNumber("1,5"), .number(1.5))
        XCTAssertThrowsError(try s.validatedNumber("0"))
        XCTAssertThrowsError(try s.validatedNumber("121"))
        XCTAssertThrowsError(try s.validatedNumber("nan"))
        XCTAssertThrowsError(try s.validatedNumber("abc"))
    }
    func testIntegerCountsDoNotAcceptFraction() throws {
        XCTAssertThrowsError(try setting(kind: "int").validatedNumber("2.5"))
    }
    func testMixedValuesAndGroupOrder() throws {
        let data = Data(#"{"settings":[{"key":"enabled","label":"Импорт","group":"автоимпорт","kind":"bool","default":true},{"key":"mode","label":"Приём","group":"режим_приёма","kind":"enum","default":"manual","options":["manual","auto"]},{"key":"silence","label":"Тишина","group":"тишина","kind":"duration_min","default":10}],"values":{"enabled":false,"mode":"auto","silence":1.5},"updated_at":{}}"#.utf8)
        let snapshot = try JSONDecoder().decode(ServerSettingsSnapshot.self, from: data)
        XCTAssertEqual(snapshot.groups, ["тишина","автоимпорт","режим_приёма"])
        XCTAssertEqual(snapshot.values["enabled"], .bool(false))
        XCTAssertEqual(snapshot.values["silence"], .number(1.5))
        XCTAssertEqual(snapshot.values["mode"]?.serverSettingText, "Автоматически")
    }
    func testUpdateBodyKeepsBooleanAndNumberTypes() throws {
        let data = try JSONEncoder().encode(["value": JSONValue.bool(false)])
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Bool])?["value"], false)
        let n = try JSONEncoder().encode(["value": JSONValue.number(1.5)])
        XCTAssertEqual((try JSONSerialization.jsonObject(with: n) as? [String: Double])?["value"], 1.5)
    }
}
