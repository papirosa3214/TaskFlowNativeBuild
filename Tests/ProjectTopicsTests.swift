import XCTest
@testable import TaskFlow

final class ProjectTopicsTests: XCTestCase {
    func testLegacyChatStillDecodes() throws {
        let chat = try JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"legacy","title":"Чат","kind":"group","created_by":"owner","members":[]}"#.utf8))
        XCTAssertNil(chat.projectID)
        XCTAssertNil(chat.parentChatID)
    }
    func testTaskTopicRetainsGroupAndTaskIdentity() throws {
        let chat = try JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"topic","title":"Задача","kind":"group","created_by":"owner","project_id":"project","parent_chat_id":"group","task_id":"task","members":[]}"#.utf8))
        XCTAssertEqual(chat.projectID, "project")
        XCTAssertEqual(chat.parentChatID, "group")
        XCTAssertEqual(chat.taskID, "task")
    }
}
