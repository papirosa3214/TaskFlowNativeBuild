import XCTest

/// Окно ленты чата: сколько последних сообщений рисуется и когда дорисовывать
/// следующие десять.
///
/// Владелец 08.11.2026: «у меня первично отображаются последние 10 сообщений,
/// при прокрутке происходит дозагруз… а сейчас что-то нет у этого дозагруза,
/// они просто как бы удалились». Дорисовку запускал `onAppear` у полоски
/// вверху ленты, но лента с 07.11 — обычный `VStack`, все строки монтируются
/// сразу, и полоска «появлялась» ровно один раз при открытии (фаза `.idle` →
/// guard) — больше никогда. Решение должно приниматься по геометрии прокрутки,
/// а не по однократному появлению, поэтому правило вынесено в чистую функцию
/// и проверяется здесь.
final class RoleChatFeedWindowTests: XCTestCase {
    @objc func testNothingHiddenDoesNotGrow() {
        XCTAssertFalse(RoleChatFeedWindow.shouldGrow(hidden: 0, nearTop: true, scrolling: true))
    }

    @objc func testNegativeHiddenDoesNotGrow() {
        // Сообщений меньше окна: скрывать нечего.
        XCTAssertFalse(RoleChatFeedWindow.shouldGrow(hidden: -3, nearTop: true, scrolling: true))
    }

    @objc func testNotNearTopDoesNotGrow() {
        XCTAssertFalse(RoleChatFeedWindow.shouldGrow(hidden: 12, nearTop: false, scrolling: true))
    }

    @objc func testIdleDoesNotGrow() {
        // Открыли короткий чат: верх виден сразу, но лента стоит на месте —
        // автодорисовка увозила ленту от низа (07.11.2026).
        XCTAssertFalse(RoleChatFeedWindow.shouldGrow(hidden: 12, nearTop: true, scrolling: false))
    }

    @objc func testPullToTopGrows() {
        XCTAssertTrue(RoleChatFeedWindow.shouldGrow(hidden: 12, nearTop: true, scrolling: true))
    }

    @objc func testGrowsTenAtATime() {
        XCTAssertEqual(RoleChatFeedWindow.step, 10)
        XCTAssertEqual(RoleChatFeedWindow.grown(window: RoleChatFeedWindow.step), 20)
        XCTAssertEqual(RoleChatFeedWindow.grown(window: 20), 30)
    }

    @objc func testEveryPullToTopGrowsAgain() {
        // Регрессия: второй и следующий дозагруз не приходил вовсе.
        // 35 сообщений: окна 10 → 20 → 30 → 40, дальше скрытых нет.
        let count = 35
        var window = RoleChatFeedWindow.step
        var grown = 0
        while RoleChatFeedWindow.shouldGrow(hidden: count - window, nearTop: true, scrolling: true) {
            window = RoleChatFeedWindow.grown(window: window)
            grown += 1
            if grown > 10 { break }
        }
        XCTAssertEqual(grown, 3)
        XCTAssertEqual(window, 40)
    }
}
