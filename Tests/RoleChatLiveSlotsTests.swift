import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// «Паспорт» живого хода (06.11.2026): лента читает только его, текст хода —
/// строка хода. Порядок и фильтр — ровно как у прежнего `visibleLiveTurns`.
final class RoleChatLiveSlotsTests: XCTestCase {
    private func slot(_ user: String, _ start: String?, date: Double?, visible: Bool = true, trigger: String? = nil) -> RoleChatLiveSlot {
        RoleChatLiveSlot(userID: user, playbackID: user + ":" + (start ?? "live"), startedAt: start,
                         startDate: date.map { Date(timeIntervalSince1970: $0) },
                         triggerMessageID: trigger, isVisible: visible)
    }

    func testInvisibleTurnsAreHidden() {
        let result = RoleChatLiveSlots.visibleSorted([slot("a", "1", date: 1, visible: false), slot("b", "2", date: 2)])
        XCTAssertEqual(result.map(\.userID), ["b"])
    }

    func testOrderedByStartThenPlaybackIDAndUndatedLast() {
        let result = RoleChatLiveSlots.visibleSorted([
            slot("c", nil, date: nil), slot("b", "2", date: 2), slot("a", "1", date: 2), slot("d", "0", date: 1),
        ])
        XCTAssertEqual(result.map(\.userID), ["d", "a", "b", "c"])
    }

    func testSameTurnWithGrownTextGivesEqualSlot() {
        // Паспорт не содержит текста: рост ответа его не меняет, и лента
        // не перерисовывается на каждую порцию.
        XCTAssertEqual(slot("a", "1", date: 1, trigger: "m1"), slot("a", "1", date: 1, trigger: "m1"))
        XCTAssertNotEqual(slot("a", "1", date: 1, visible: false), slot("a", "1", date: 1, visible: true))
    }
}
