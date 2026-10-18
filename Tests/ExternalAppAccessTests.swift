import XCTest
#if !EXTERNAL_ACCESS_STANDALONE
@testable import TaskFlow
#endif

final class ExternalAppAccessTests: XCTestCase {
    private func probe(_ json: String) throws -> ThingsAccessProbe {
        try JSONDecoder().decode(ThingsAccessProbe.self, from: Data(json.utf8))
    }

    func testSuccessfulEmptyListConfirmsReading() throws {
        XCTAssertTrue(try probe(#"{"ok":true,"data":{"ok":true,"result":"[]"}}"#).readAvailable)
    }

    func testHostOnlineDoesNotHideMCPPermissionError() throws {
        XCTAssertFalse(try probe(#"{"ok":true,"data":{"ok":true,"result":"ERROR: Operation not permitted"}}"#).readAvailable)
    }

    func testFailedOrMalformedResponseNeverMeansAvailable() throws {
        for json in [#"{"ok":false,"error":"offline"}"#,
                     #"{"ok":true,"data":{"ok":false,"result":"[]"}}"#,
                     #"{"ok":true,"data":{"ok":true,"result":""}}"#,
                     #"{"ok":true,"data":{"result":"{}"}}"#] {
            XCTAssertFalse(try probe(json).readAvailable, json)
        }
    }
}
