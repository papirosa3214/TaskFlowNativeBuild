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
    func testMillisecondsConvertInputBoundsAndDisplay() throws {
        let data = Data(#"{"key":"pause","label":"Пауза","group":"таймауты","kind":"duration_ms","default":30000,"min":1000,"max":120000}"#.utf8)
        let seconds = try JSONDecoder().decode(ServerSetting.self, from: data)
        XCTAssertEqual(seconds.displayText(.number(30000)), "30 с")
        XCTAssertEqual(try seconds.validatedNumber("1,5"), .number(1500))
        XCTAssertThrowsError(try seconds.validatedNumber("121"))
        let minutes = try JSONDecoder().decode(ServerSetting.self, from: Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "30000", with: "300000").utf8))
        XCTAssertEqual(minutes.displayText(.number(300000)), "5 мин")
        XCTAssertEqual(try minutes.validatedNumber("1,5"), .number(90000))
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
