import XCTest
@testable import TaskFlow

final class RoleComposioTests: XCTestCase {
    func testWholeCatalogAndEmptySelectionRemainDifferent() throws {
        let decoder = JSONDecoder()
        let all = try decoder.decode(RoleComposio.self, from: Data(#"{"enabled":true,"toolkits":null,"configured":true,"available":true,"catalog":[],"error":null}"#.utf8))
        let none = try decoder.decode(RoleComposio.self, from: Data(#"{"enabled":true,"toolkits":[],"configured":true,"available":true,"catalog":[],"error":null}"#.utf8))
        XCTAssertNil(all.toolkits)
        XCTAssertEqual(none.toolkits, [])
    }

    func testConnectionStatusAndFailureDecode() throws {
        let settings = try JSONDecoder().decode(RoleComposio.self, from: Data(#"{"enabled":false,"toolkits":["github"],"configured":true,"available":false,"catalog":[{"slug":"github","name":"GitHub","connected":false,"noAuth":false}],"error":"Unavailable"}"#.utf8))
        XCTAssertFalse(settings.available)
        XCTAssertFalse(settings.catalog[0].connected)
        XCTAssertEqual(settings.error, "Unavailable")
    }
}
