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

    @MainActor
    func testDueEditorRepeatMapsToRoutineRules() {
        let model = RoutineFormViewModel(api: APIClient())
        model.repeatChoice = "none"
        XCTAssertEqual(model.ruleKind, "once")
        model.repeatChoice = "weekdays"
        XCTAssertEqual(model.ruleKind, "weekly_days")
        XCTAssertEqual(model.ruleExpr, "1,2,3,4,5")
        XCTAssertEqual(model.repeatChoice, "weekdays")
        // 28.10.2026 — среда, 12:00 по Москве.
        let wednesday = Date(timeIntervalSince1970: 1_793_178_000)
        model.startDate = wednesday
        model.repeatChoice = "weekly"
        XCTAssertEqual(model.ruleExpr, "3")
        model.repeatChoice = "monthly"
        XCTAssertEqual(model.ruleExpr, "28")
        model.startMinutes = 7 * 60 + 15
        XCTAssertEqual(model.timeLocal, "07:15")
    }
}
