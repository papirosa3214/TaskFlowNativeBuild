import XCTest
@testable import TaskFlow

final class RoutineEditingTests: XCTestCase {
    func testClearedTemplateFieldsEncodeAsNull() throws {
        let payload = ApiSchedulePayload(title: "Задание")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        for key in ["description", "project_id", "assignee_id", "duration_min"] {
            XCTAssertTrue(object[key] is NSNull, "Снятая настройка должна очищаться сервером: \(key)")
        }
    }

    func testExistingTemplateFlagsSurviveEncoding() throws {
        var payload = ApiSchedulePayload(title: "Задание", labels: ["Новости"], requiresReviewerReview: true, needsResearch: true)
        payload.description = "Уточнённое задание"
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(object["labels"] as? [String], ["Новости"])
        XCTAssertEqual(object["requires_reviewer_review"] as? Bool, true)
        XCTAssertEqual(object["needs_research"] as? Bool, true)
        XCTAssertEqual(object["description"] as? String, "Уточнённое задание")
    }
}
