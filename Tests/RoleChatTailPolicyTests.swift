import XCTest
@testable import TaskFlow

/// Политика слежения за хвостом переписки (окно чата с ролями).
///
/// Смысл: лента не должна ни резко уезжать вниз при росте содержимого, ни
/// «залипать» — потерять новое сообщение из виду после того, как
/// пользователь хоть раз прокрутил переписку.
final class RoleChatTailPolicyTests: XCTestCase {
    // MARK: - Вход в чат

    func testEnteringChatFollowsTail() {
        var policy = ChatTailPolicy()
        policy.handle(.entered)
        XCTAssertTrue(policy.followsTail)
    }

    // MARK: - Пользователь ушёл читать историю

    func testScrollingUpStopsFollowingTail() {
        var policy = ChatTailPolicy()
        policy.handle(.userScrolled(nearBottom: false))
        XCTAssertFalse(policy.followsTail, "После ухода в историю лента не должна догонять хвост сама")
    }

    func testScrollingBackToBottomResumesFollowingTail() {
        var policy = ChatTailPolicy()
        policy.handle(.userScrolled(nearBottom: false))
        policy.handle(.userScrolled(nearBottom: true))
        XCTAssertTrue(policy.followsTail, "Вернувшись к хвосту, лента снова следит за новыми сообщениями")
    }

    // MARK: - Рост содержимого не решает за пользователя

    func testContentGrowthDoesNotChangeDecisionWhileUserIsReadingHistory() {
        var policy = ChatTailPolicy()
        policy.handle(.userScrolled(nearBottom: false))
        // Рост содержимого приходит как геометрия, а не как намерение.
        policy.handle(.userScrolled(nearBottom: false))
        XCTAssertFalse(policy.followsTail)
    }

    func testGeometryWithoutUserDrivingDoesNotResumeFollowing() {
        var policy = ChatTailPolicy()
        policy.handle(.userScrolled(nearBottom: false))
        // Пользователь не трогает ленту — решение остаётся прежним.
        XCTAssertFalse(policy.followsTail)
    }

    // MARK: - Явные переходы приложения

    func testJumpToTailTurnsFollowingOn() {
        var policy = ChatTailPolicy()
        policy.handle(.userScrolled(nearBottom: false))
        policy.handle(.jumpedToTail)
        XCTAssertTrue(policy.followsTail, "Отправка сообщения возвращает слежение за хвостом")
    }

    func testJumpToMessageTurnsFollowingOff() {
        var policy = ChatTailPolicy()
        policy.handle(.jumpedToMessage)
        XCTAssertFalse(policy.followsTail, "Переход к конкретному сообщению не должен отменяться ростом содержимого")
    }

    func testJumpToMessageStopsUserDriving() {
        var policy = ChatTailPolicy()
        policy.userStartedDriving()
        policy.handle(.jumpedToMessage)
        XCTAssertFalse(policy.userDrivesScroll)
        XCTAssertFalse(policy.followsTail)
    }

    // MARK: - Кто ведёт ленту

    func testUserDrivingIsTrackedSeparatelyFromFollowing() {
        var policy = ChatTailPolicy()
        policy.userStartedDriving()
        XCTAssertTrue(policy.userDrivesScroll)
        XCTAssertTrue(policy.followsTail, "Пока лентой ведут мы, решение не меняется само")
    }

    func testStoppingDrivingAppliesFinalPosition() {
        var policy = ChatTailPolicy()
        policy.userStartedDriving()
        policy.userStoppedDriving(nearBottom: false)
        XCTAssertFalse(policy.userDrivesScroll)
        XCTAssertFalse(policy.followsTail)
    }

    func testStoppingDrivingNearBottomKeepsFollowing() {
        var policy = ChatTailPolicy()
        policy.userStartedDriving()
        policy.userStoppedDriving(nearBottom: true)
        XCTAssertFalse(policy.userDrivesScroll)
        XCTAssertTrue(policy.followsTail)
    }

    // MARK: - Обратимость

    func testPolicyIsReversibleBothWays() {
        var policy = ChatTailPolicy()
        for nearBottom in [false, true, false, true] {
            policy.handle(.userScrolled(nearBottom: nearBottom))
            XCTAssertEqual(policy.followsTail, nearBottom)
        }
    }
}
