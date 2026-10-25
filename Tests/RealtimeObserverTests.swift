import XCTest
@testable import TaskFlow

/// У `RealtimeClient` слот `onEvent` один, и его держит приложение (TaskStore).
/// Экранам нужен свой канал: несколько подписчиков должны получать одно
/// событие, а снятие подписки не должно ломать остальных. Иначе каждый экран
/// шторки роли открывает свой WebSocket — в журнале сервера это десятки
/// переподключений в минуту.
@MainActor
final class RealtimeObserverTests: XCTestCase {
    func testSeveralObserversGetSameEvent() {
        let client = RealtimeClient()
        var first = 0
        var second = 0
        client.addObserver { _ in first += 1 }
        client.addObserver { _ in second += 1 }

        client.dispatchToSubscribers(.taskChanged(taskID: "card"))

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }

    func testRemovingObserverKeepsOthersAlive() {
        let client = RealtimeClient()
        var first = 0
        var second = 0
        let firstID = client.addObserver { _ in first += 1 }
        client.addObserver { _ in second += 1 }

        client.dispatchToSubscribers(.taskChanged(taskID: "card"))
        client.removeObserver(firstID)
        client.dispatchToSubscribers(.taskChanged(taskID: "card"))

        XCTAssertEqual(first, 1, "снятый подписчик больше не должен получать события")
        XCTAssertEqual(second, 2, "остальные подписчики продолжают работать")
    }

    func testLegacySlotStillWorksAlongsideObservers() {
        let client = RealtimeClient()
        var legacy = 0
        var observer = 0
        client.onEvent = { _ in legacy += 1 }
        client.addObserver { _ in observer += 1 }

        client.dispatchToSubscribers(.taskChanged(taskID: "card"))

        XCTAssertEqual(legacy, 1, "слот приложения (TaskStore) продолжает работать")
        XCTAssertEqual(observer, 1)
    }

    func testRemovingUnknownObserverIsHarmless() {
        let client = RealtimeClient()
        client.removeObserver(UUID())
    }
}
