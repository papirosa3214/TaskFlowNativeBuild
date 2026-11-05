import Foundation

@main
struct UnreadBadgePolicyHostTests {
    static func main() {
        todayBadgeShowsUntilTabIsOpened()
        openingTabRemembersTheDay()
        nextDayBadgeReturns()
        openTopicShowsNoCount()
        print("PASS unread badge policy")
    }

    private static func todayBadgeShowsUntilTabIsOpened() {
        check(UnreadBadgePolicy.todayTabCount(dueToday: 3, seenDate: "", today: "2026-11-05", isOnTodayTab: false) == 3, "badge is hidden before the tab was opened")
        check(UnreadBadgePolicy.todayTabCount(dueToday: 3, seenDate: "", today: "2026-11-05", isOnTodayTab: true) == 0, "badge stays while the tab is open")
        check(UnreadBadgePolicy.todayTabCount(dueToday: 3, seenDate: "2026-11-05", today: "2026-11-05", isOnTodayTab: false) == 0, "badge returned after the tab was seen today")
    }

    private static func openingTabRemembersTheDay() {
        check(UnreadBadgePolicy.todaySeenDate(current: "", today: "2026-11-05", isOnTodayTab: true) == "2026-11-05", "opening the tab is not remembered")
        check(UnreadBadgePolicy.todaySeenDate(current: "2026-11-04", today: "2026-11-05", isOnTodayTab: false) == "2026-11-04", "another tab marked today as seen")
    }

    private static func nextDayBadgeReturns() {
        check(UnreadBadgePolicy.todayTabCount(dueToday: 2, seenDate: "2026-11-04", today: "2026-11-05", isOnTodayTab: false) == 2, "badge did not return next day")
    }

    private static func openTopicShowsNoCount() {
        check(UnreadBadgePolicy.topicCount(unread: 6, isOpen: true) == 0, "open topic keeps its count")
        check(UnreadBadgePolicy.topicCount(unread: 6, isOpen: false) == 6, "closed topic lost its count")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }
}
