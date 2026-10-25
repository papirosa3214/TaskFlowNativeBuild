import XCTest
@testable import TaskFlow

/// Поведение ленты при пересборке содержимого переписки (окно чата с
/// ролями). Диагноз взят из лога на телефоне: содержимое ленты усыхает на
/// сотни пунктов при подмене живого пузыря готовым сообщением, смещение при
/// этом остаётся прежним — и лента оказывается либо в пустоте, либо с
/// растущим ответом под нижним краем.
final class RoleChatTailFollowTests: XCTestCase {
    // MARK: - Возврат к хвосту

    func testGrownContentWhileAtTailIsCompensated() {
        XCTAssertTrue(ChatFeedTailFollow.needsCompensation(heightDelta: 120, wasAtTail: true),
                      "Вырос ответ, а пользователь был у хвоста — лента обязана остаться в хвосте")
    }

    func testShrunkContentWhileAtTailIsCompensated() {
        XCTAssertTrue(ChatFeedTailFollow.needsCompensation(heightDelta: -900, wasAtTail: true),
                      "Содержимое уселось — без возврата под лентой остаётся пустота")
    }

    func testContentChangeWhileReadingHistoryIsNotCompensated() {
        XCTAssertFalse(ChatFeedTailFollow.needsCompensation(heightDelta: 120, wasAtTail: false),
                       "Читающему историю лента догонять хвост не должна")
    }

    // MARK: - Мелкие колебания

    func testTinyHeightChangesAreIgnored() {
        XCTAssertFalse(ChatFeedTailFollow.needsCompensation(heightDelta: 1, wasAtTail: true),
                       "Колебание на пункт — это дыхание layout'а, лента не должна прыгать")
        XCTAssertFalse(ChatFeedTailFollow.needsCompensation(heightDelta: -2, wasAtTail: true))
    }

    // MARK: - Где считается «хвост»

    func testContentEndingOnScreenCountsAsTail() {
        var follow = ChatFeedTailFollow()
        follow.update(distanceToBottom: -30)
        XCTAssertTrue(follow.wasAtTail, "Низ переписки у края экрана — это хвост")
    }

    func testContentEndingWellAboveScreenIsNotTail() {
        var follow = ChatFeedTailFollow()
        follow.update(distanceToBottom: -1500)
        XCTAssertFalse(follow.wasAtTail, "Пустота под перепиской — это не хвост")
    }

    func testTailStateIsRememberedBetweenUpdates() {
        var follow = ChatFeedTailFollow()
        follow.update(distanceToBottom: -30)
        XCTAssertTrue(follow.wasAtTail)
        follow.update(distanceToBottom: -900)
        XCTAssertFalse(follow.wasAtTail)
    }

    // MARK: - Доводка до хвоста

    func testNotReachedTailIsPulledDown() {
        XCTAssertTrue(ChatFeedTailFollow.needsPullToTail(distanceToBottom: -7, wasAtTail: true),
                      "Лента встала в 7 pt от края вместо штатных 16 — её надо довести")
    }

    func testSeatAtTailNeedsNoPull() {
        XCTAssertFalse(ChatFeedTailFollow.needsPullToTail(distanceToBottom: -16, wasAtTail: true),
                       "Лента уже на месте — дёргать её нельзя")
    }

    func testTailFarAboveIsPulledDown() {
        XCTAssertTrue(ChatFeedTailFollow.needsPullToTail(distanceToBottom: 2342, wasAtTail: true))
    }

    func testReadingHistoryIsNotPulledDown() {
        XCTAssertFalse(ChatFeedTailFollow.needsPullToTail(distanceToBottom: -7, wasAtTail: false),
                       "Читающему историю лента догонять хвост не должна")
    }
}
