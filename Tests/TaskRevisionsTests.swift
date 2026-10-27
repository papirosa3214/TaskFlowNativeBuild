import XCTest

final class TaskRevisionsTests: XCTestCase {
    func testReconnectAloneDoesNotWakeCards() {
        var revisions = TaskRevisions()
        let before = revisions.revision(for: "card")
        revisions.connected()
        XCTAssertEqual(revisions.revision(for: "card"), before)
    }

    func testCatchUpWakesOnlyChangedCards() {
        var revisions = TaskRevisions()
        revisions.catchUp(changedTaskIDs: ["card"])
        XCTAssertEqual(revisions.revision(for: "card"), 1)
        XCTAssertEqual(revisions.activity["card"], 1)
        XCTAssertEqual(revisions.revision(for: "other"), 0)
        XCTAssertNil(revisions.activity["other"])
    }

    func testUnknownCatchUpWakesEveryCard() {
        var revisions = TaskRevisions()
        revisions.catchUp(changedTaskIDs: nil)
        XCTAssertEqual(revisions.revision(for: "card"), 1)
        XCTAssertEqual(revisions.revision(for: "other"), 1)
        XCTAssertEqual(revisions.stale, 1)
    }

    func testTaskEventWakesTaskAndParent() {
        var revisions = TaskRevisions()
        revisions.taskChanged("child", parent: "card")
        XCTAssertEqual(revisions.revision(for: "child"), 1)
        XCTAssertEqual(revisions.revision(for: "card"), 1)
    }
}
