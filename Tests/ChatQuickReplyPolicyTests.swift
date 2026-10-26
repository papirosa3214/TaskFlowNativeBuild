import XCTest

/// Правило показа быстрых вариантов ответа (26.10.2026).
///
/// Варианты принадлежат последнему ВИДИМОМУ сообщению ленты, если оно не
/// моё. Раньше правило брало последнее СЫРОЕ сообщение и дополнительно
/// требовало совпадения с последним видимым: следом лежала скрытая строка
/// координации или дубль доигранного живого хода — проверка не проходила,
/// вопрос стоял прямо над плашками, а кнопок не было.
final class ChatQuickReplyPolicyTests: XCTestCase {

    private struct Message: QuickReplyMessage {
        let id: String
        let fromUserID: String?
        let quickReplies: [String]?
    }

    private func message(_ id: String, _ from: String?, _ replies: [String]? = nil) -> Message {
        Message(id: id, fromUserID: from, quickReplies: replies)
    }

    /// Служебная строка скрыта из ленты — варианты вопроса остаются.
    func testVariantsStayWhenServiceRowIsHidden() {
        let question = message("q", "role_secretary", ["Да", "Нет"])
        // Видимая лента: только вопрос. Скрытая строка координации в неё не входит.
        XCTAssertEqual(ChatQuickReplyPolicy.replies(for: question, in: [question], ownerID: "u1"),
                       ["Да", "Нет"])
    }

    /// Свой ответ снимает актуальность вариантов.
    func testOwnerReplyRemovesVariants() {
        let question = message("q", "role_secretary", ["Да", "Нет"])
        let owner = message("o", "u1", nil)
        XCTAssertNil(ChatQuickReplyPolicy.replies(for: question, in: [question, owner], ownerID: "u1"))
    }

    /// Варианты принадлежат СВОЕМУ сообщению (26.10.2026, жалоба владельца:
    /// «плашки видны только у последнего сообщения»). Ответ роли, пришедший
    /// ПОЗЖЕ, не отменяет варианты вопроса — он живёт у своего сообщения.
    func testVariantsSurviveLaterRoleMessage() {
        let question = message("q", "role_secretary", ["Да", "Нет"])
        let reply = message("r", "role_secretary", nil)
        XCTAssertEqual(ChatQuickReplyPolicy.replies(for: question, in: [question, reply], ownerID: "u1"),
                       ["Да", "Нет"])
    }

    /// Два предложения роли — у каждого свои варианты (владелец отвечает на
    /// конкретный вопрос, а не на «последний вообще»).
    func testEachProposalKeepsItsOwnVariants() {
        let first = message("q1", "role_secretary", ["Да"])
        let second = message("q2", "role_secretary", ["Первый", "Второй"])
        let feed = [first, second]
        XCTAssertEqual(ChatQuickReplyPolicy.replies(for: first, in: feed, ownerID: "u1"), ["Да"])
        XCTAssertEqual(ChatQuickReplyPolicy.replies(for: second, in: feed, ownerID: "u1"),
                       ["Первый", "Второй"])
    }

    /// Ответ владельца снимает актуальность вариантов вопроса — даже если
    /// между вопросом и ответом стоял ответ роли.
    func testOwnerReplyAfterRoleMessageStillRemovesVariants() {
        let question = message("q", "role_secretary", ["Да", "Нет"])
        let reply = message("r", "role_secretary", nil)
        let owner = message("o", "u1", nil)
        XCTAssertNil(ChatQuickReplyPolicy.replies(for: question, in: [question, reply, owner], ownerID: "u1"))
    }

    func testAtMostThreeVariants() {
        let question = message("q", "role_secretary", ["1", "2", "3", "4"])
        XCTAssertEqual(ChatQuickReplyPolicy.replies(for: question, in: [question], ownerID: "u1"),
                       ["1", "2", "3"])
    }

    func testOwnMessageAndEmptyVariantsShowNothing() {
        let own = message("o", "u1", ["1"])
        XCTAssertNil(ChatQuickReplyPolicy.replies(for: own, in: [own], ownerID: "u1"))
        let empty = message("q", "role_secretary", [])
        XCTAssertNil(ChatQuickReplyPolicy.replies(for: empty, in: [empty], ownerID: "u1"))
        let none = message("q", "role_secretary", nil)
        XCTAssertNil(ChatQuickReplyPolicy.replies(for: none, in: [none], ownerID: "u1"))
    }
}
