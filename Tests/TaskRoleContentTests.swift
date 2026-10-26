import Foundation
import XCTest
@testable import TaskFlow
final class TaskRoleContentTests: XCTestCase {
    func testExistingReviewBecomesSameV1Contract() throws {
        let text = #"Ревьюер вернул на доработку: [{"id":"D1","priority":"P1","location":"server/file.ts:10","observation":"После сброса старый контекст"}]"#
        let json = try XCTUnwrap(TaskRoleContent.json(in: text))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["ok"] as? Bool, true)
        let blocks = try XCTUnwrap(object["output"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue((blocks.last?["text"] as? String)?.contains("После сброса старый контекст") == true)
        XCTAssertTrue((blocks.last?["text"] as? String)?.contains("server/file.ts:10") == true)
    }
    func testCanonicalEnvelopePassesUnchangedAndPlainTextRemainsPlain() {
        let json = #"{"schema_version":1,"ok":true,"output":[{"type":"text","text":"Готово"}]}"#
        XCTAssertEqual(TaskRoleContent.json(in: json), json)
        XCTAssertEqual(TaskRoleContent.json(in: "```tf-json\n" + json + "\n```"), json)
        XCTAssertNil(TaskRoleContent.json(in: "Обычный текст владельца"))
        XCTAssertNil(TaskRoleContent.json(in: "changes_requested: [broken"))
        XCTAssertNil(TaskRoleContent.json(in: #"{"foo":1}"#))
    }
    func testMachinePrefixAndEmptyDefectsDoNotLeakRawArrays() throws {
        let json = try XCTUnwrap(TaskRoleContent.json(in: #"changes_requested: [{"id":"D2","observation":"Исправить"}]"#))
        XCTAssertTrue(json.contains("Исправить"))
        XCTAssertNil(TaskRoleContent.json(in: "changes_requested: []"))
    }
}
