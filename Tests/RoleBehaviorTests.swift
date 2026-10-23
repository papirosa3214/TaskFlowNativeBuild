import XCTest
@testable import TaskFlow

final class RoleBehaviorTests: XCTestCase {
    func testTemplateSelectionDoesNotReplaceActiveBehaviorAndConflictKeepsDraft() {
        let active = RoleBehavior(role: "developer", text: "Активная личность", gender: .male, version: 4, templates: [])
        var draft = RoleBehaviorDraft(behavior: active)
        draft.select(RoleBehaviorTemplate(id: "warm", name: "Тёплый", text: "Другой характер", gender: .female, builtin: true))
        XCTAssertEqual(active.text, "Активная личность")
        XCTAssertEqual(draft.text, "Другой характер")
        XCTAssertEqual(draft.gender, .female)
        draft.hasConflict = true
        draft.adoptVersion(5)
        XCTAssertEqual(draft.text, "Другой характер")
        XCTAssertEqual(draft.gender, .female)
        XCTAssertEqual(draft.expectedVersion, 5)
        XCTAssertFalse(draft.hasConflict)
    }

    func testGenderChangeAloneIsAnUnsavedBehaviorChange() {
        let active = RoleBehavior(role: "architect", text: "Я проектирую", gender: .male, version: 1, templates: [])
        var draft = RoleBehaviorDraft(behavior: active)
        XCTAssertFalse(draft.differs(from: active))
        draft.gender = .female
        XCTAssertTrue(draft.differs(from: active))
        XCTAssertEqual(draft.text, active.text)
        XCTAssertEqual(active.gender, .male)
    }

    func testDecodesGenderAndBuiltinTemplates() throws {
        let data = Data(#"{"role":"critic","text":"Я проверила","gender":"female","version":2,"templates":[{"id":"precise","name":"Точный","text":"Я проверил","gender":"male","builtin":true}]}"#.utf8)
        let behavior = try JSONDecoder().decode(RoleBehavior.self, from: data)
        XCTAssertEqual(behavior.gender, .female)
        XCTAssertTrue(behavior.templates[0].builtin)
        XCTAssertEqual(behavior.templates[0].gender, .male)
    }
}
