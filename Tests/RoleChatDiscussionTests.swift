import Foundation
import XCTest
@testable import TaskFlow

/// Обсуждение работающей карточки на клиенте (карточка 252c400e, этап 5).
final class RoleChatDiscussionTests: XCTestCase {

    private func decode(_ json: String) throws -> RoleChatDiscussion {
        try JSONDecoder().decode(RoleChatDiscussion.self, from: Data(json.utf8))
    }

    func testDecodesServerSnapshot() throws {
        let discussion = try decode(#"{"discussion_id":"d1","chat_id":"c1","task_id":"t1","subtask_id":"s1","state":"closed","delivery_state":"delivered","handoff_id":"h1","summary_id":"sum1","messages":4,"accepted_at":"2026-10-25 04:00:00"}"#)
        XCTAssertEqual(discussion.discussionID, "d1")
        XCTAssertEqual(discussion.state, .closed)
        XCTAssertEqual(discussion.deliveryState, .delivered)
        XCTAssertEqual(discussion.statusTitle, "Итог получен исполнителем")
        XCTAssertFalse(discussion.isAwaitingDelivery)
    }

    func testAwaitingDeliveryIsVisible() throws {
        let discussion = try decode(#"{"discussion_id":"d1","chat_id":"c1","task_id":"t1","subtask_id":"s1","state":"closed","delivery_state":"awaiting","messages":2}"#)
        XCTAssertTrue(discussion.isAwaitingDelivery)
        XCTAssertEqual(discussion.statusTitle, "Итог сохранён, ожидает доставки")
        XCTAssertNotNil(discussion.statusDetail)
    }

    /// Неизвестный серверу статус не ломает клиент.
    func testUnknownStatusDoesNotBreakDecoding() throws {
        let discussion = try decode(#"{"discussion_id":"d1","chat_id":"c1","task_id":"t1","subtask_id":"s1","state":"quarantined","delivery_state":"teleported","messages":1}"#)
        XCTAssertEqual(discussion.state, .unknown)
        XCTAssertEqual(discussion.deliveryState, .unknown)
    }
}
