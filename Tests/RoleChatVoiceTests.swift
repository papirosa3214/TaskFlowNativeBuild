import Foundation
import XCTest
@testable import TaskFlow

final class RoleChatVoiceTests: XCTestCase {
    func testAudioAttachmentAndTaskBindingDecode() throws {
        let decoder = JSONDecoder()
        let chat = try decoder.decode(RoleChat.self, from: Data(#"{"id":"c1","kind":"direct","created_by":"u1","task_id":"t1","members":[]}"#.utf8))
        XCTAssertEqual(chat.taskID, "t1")

        let message = try decoder.decode(RoleChatMessage.self, from: Data(#"{"id":"m1","text":"Привет","attachments":[{"id":"a1","file_name":"voice.m4a","mime":"audio/mp4","size":42}]}"#.utf8))
        XCTAssertEqual(message.attachments?.first?.id, "a1")
        XCTAssertEqual(message.attachments?.first?.mime, "audio/mp4")
        XCTAssertEqual(message.attachments?.first?.isVoiceRecording, true)

        let currentServer = try decoder.decode(RoleChatMessage.self, from: Data(#"{"id":"m2","text":"","attachments":[{"id":"a2","file_name":"voice.m4a","mime":"application/octet-stream"}]}"#.utf8))
        XCTAssertEqual(currentServer.attachments?.first?.isVoiceRecording, true)
    }

    func testDraftResponseAcceptsTaskIDAndTaskObject() throws {
        let decoder = JSONDecoder()
        let direct = try decoder.decode(RoleChatDraftResult.self, from: Data(#"{"task_id":"t1"}"#.utf8))
        let wrapped = try decoder.decode(RoleChatDraftResult.self, from: Data(#"{"task":{"id":"t2"}}"#.utf8))
        XCTAssertEqual(direct.createdTaskID, "t1")
        XCTAssertEqual(wrapped.createdTaskID, "t2")
    }
}
