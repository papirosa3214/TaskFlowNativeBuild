import XCTest
@testable import TaskFlow

/// Различие «сообщение сохранено» и «передано исполнителю» в ленте (карточка
/// b504958a, контракт §10). Признак доставки относится к СООБЩЕНИЮ ВЛАДЕЛЬЦА,
/// которому роль должна ответить: под ответом роли его показывать нельзя.
///
/// RED на старом коде: правило показа значка не существовало — тест не
/// собирался, а экран рисовал признак доставки под ответом роли.
final class ChatDeliveryBadgeTests: XCTestCase {
    private func message(fromUserID: String, delivery: String?) throws -> RoleChatMessage {
        let state = delivery.map { ",\"queue_delivery_state\":\"\($0)\"" } ?? ""
        let json = "{\"id\":\"m1\",\"text\":\"Сделай вот это\",\"chat_id\":\"c1\","
            + "\"from_user_id\":\"\(fromUserID)\",\"is_session_marker\":false\(state)}"
        return try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
    }

    func testOwnMessageShowsDeliveryState() throws {
        let message = try message(fromUserID: "u1", delivery: "accepted")
        XCTAssertEqual(
            ChatDeliveryBadgePolicy.badge(for: message, isOwnMessage: true, isAgentReply: false),
            .accepted
        )
    }

    func testOwnMessageKeepsEveryServerState() throws {
        let states: [(String, ChatMessageDeliveryState)] = [
            ("saved", .saved), ("queued", .queued), ("accepted", .accepted), ("stale", .stale),
        ]
        for (raw, expected) in states {
            let message = try message(fromUserID: "u1", delivery: raw)
            XCTAssertEqual(
                ChatDeliveryBadgePolicy.badge(for: message, isOwnMessage: true, isAgentReply: false),
                expected
            )
        }
    }

    func testRoleAnswerHasNoDeliveryBadge() throws {
        let message = try message(fromUserID: "role_builder", delivery: "saved")
        XCTAssertNil(ChatDeliveryBadgePolicy.badge(for: message, isOwnMessage: false, isAgentReply: true))
    }

    func testMessageWithoutServerStateHasNoBadge() throws {
        let message = try message(fromUserID: "u1", delivery: nil)
        XCTAssertNil(ChatDeliveryBadgePolicy.badge(for: message, isOwnMessage: true, isAgentReply: false))
    }

    func testLabelsTellSavedFromDelivered() {
        XCTAssertEqual(ChatMessageDeliveryState.saved.label, "Сохранено")
        XCTAssertEqual(ChatMessageDeliveryState.queued.label, "В очереди")
        XCTAssertEqual(ChatMessageDeliveryState.accepted.label, "Передано исполнителю")
        XCTAssertEqual(ChatMessageDeliveryState.stale.label, "Не передано")
        XCTAssertTrue(ChatMessageDeliveryState.stale.isProblem)
    }
}
