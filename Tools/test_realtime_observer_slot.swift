import Foundation

@main
struct RealtimeObserverSlotHostTests {
    static func main() {
        replacingRemovesPreviousSubscription()
        clearingRemovesSubscriptionOnce()
        emptySlotRemovesNothing()
        print("PASS realtime observer slot")
    }

    /// Экран вернулся из перехода: `.task` сработал снова, а событие
    /// не должно доставляться дважды.
    private static func replacingRemovesPreviousSubscription() {
        var slot = RealtimeObserverSlot<Int>()
        var removed: [Int] = []

        slot.replace(add: { 1 }, remove: { removed.append($0) })
        check(slot.isActive, "slot is not active after subscribing")
        check(removed.isEmpty, "first subscription removed something")

        slot.replace(add: { 2 }, remove: { removed.append($0) })
        check(removed == [1], "previous subscription survived a repeat subscribe: \(removed)")
    }

    private static func clearingRemovesSubscriptionOnce() {
        var slot = RealtimeObserverSlot<Int>()
        var removed: [Int] = []
        slot.replace(add: { 7 }, remove: { removed.append($0) })

        slot.clear(remove: { removed.append($0) })
        slot.clear(remove: { removed.append($0) })

        check(removed == [7], "clear removed the wrong tokens: \(removed)")
        check(!slot.isActive, "slot stayed active after clear")
    }

    private static func emptySlotRemovesNothing() {
        var slot = RealtimeObserverSlot<Int>()
        var removed: [Int] = []
        slot.clear(remove: { removed.append($0) })
        check(removed.isEmpty, "empty slot removed a token")
        check(!slot.isActive, "empty slot reports active")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }
}
