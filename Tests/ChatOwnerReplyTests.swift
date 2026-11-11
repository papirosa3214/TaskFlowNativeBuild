import XCTest

final class ChatOwnerReplyTests: XCTestCase {
    func testReplyKeepsMessageAndTrimmedText() {
        let target = ChatOwnerReply.target(id: "m-1", text: "  Срок переносим на пятницу  ", isSessionMarker: false)
        XCTAssertEqual(target, ChatOwnerReply.Target(messageID: "m-1", excerpt: "Срок переносим на пятницу"))
    }

    func testReplyToAttachmentWithoutText() {
        let target = ChatOwnerReply.target(id: "m-2", text: " \n ", isSessionMarker: false)
        XCTAssertEqual(target?.excerpt, "Вложение")
        XCTAssertEqual(target?.messageID, "m-2")
    }

    func testSessionMarkerCannotBeRepliedTo() {
        XCTAssertNil(ChatOwnerReply.target(id: "mark", text: "Новая сессия", isSessionMarker: true))
    }

    func testEmptyIdentifierIsNotAReply() {
        XCTAssertNil(ChatOwnerReply.target(id: "  ", text: "текст", isSessionMarker: false))
    }
}
