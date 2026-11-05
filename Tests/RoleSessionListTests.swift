import XCTest
@testable import TaskFlow

final class RoleSessionListTests: XCTestCase {
    private func item(_ id: String, others: [String], kind: String = "direct", room: String? = nil,
                      parent: String? = nil, project: String? = nil, last: String? = nil) -> RoleSessionCandidate {
        RoleSessionCandidate(id: id, kind: kind, roomKind: room, parentChatID: parent, projectID: project,
                             otherMemberIDs: others, lastActivity: last)
    }

    func testRoleShowsOnlyItsOwnPrivateSessions() {
        let list = [
            item("mine", others: ["secretary"], last: "2026-11-05 01:00:00"),
            item("other", others: ["designer"], last: "2026-11-05 02:00:00"),
            item("both", others: ["secretary", "designer"], kind: "group", last: "2026-11-05 03:00:00"),
        ]
        XCTAssertEqual(RoleSessionList.select(list, scope: .role("secretary")), ["mine"])
    }

    func testPersonalRoomIsAnOrdinarySessionSortedByDate() {
        let list = [
            item("room", others: ["secretary"], room: "personal", last: "2026-11-03 01:00:00"),
            item("fresh", others: ["secretary"], last: "2026-11-05 01:00:00"),
            item("empty", others: ["secretary"]),
        ]
        XCTAssertEqual(RoleSessionList.select(list, scope: .role("secretary")), ["fresh", "room", "empty"])
    }

    func testGroupsCollectEveryMultiRoleSessionSortedByDate() {
        let list = [
            item("single", others: ["secretary"], last: "2026-11-05 05:00:00"),
            item("old", others: ["secretary", "designer"], kind: "group", last: "2026-11-01 01:00:00"),
            item("topic", others: ["builder", "qa"], kind: "group", parent: "project", project: "p", last: "2026-11-04 01:00:00"),
            item("two", others: ["builder", "qa"], last: "2026-11-02 01:00:00"),
        ]
        XCTAssertEqual(RoleSessionList.select(list, scope: .groups), ["topic", "two", "old"])
    }

    func testCommonAndProjectChatsLiveInGroups() {
        let list = [
            item("common", others: ["a", "b"], kind: "group", room: "common", last: "2026-11-02 01:00:00"),
            item("project", others: ["a", "b"], kind: "group", project: "p", last: "2026-11-03 01:00:00"),
        ]
        XCTAssertEqual(RoleSessionList.select(list, scope: .groups), ["project", "common"])
        XCTAssertEqual(RoleSessionList.select(list, scope: .role("a")), [])
    }

    func testRoleDmStaysOutOfSessions() {
        let list = [item("dm", others: ["a"], room: "dm")]
        XCTAssertEqual(RoleSessionList.select(list, scope: .groups), [])
        XCTAssertEqual(RoleSessionList.select(list, scope: .role("a")), [])
    }

    func testScopeSurvivesStorageRoundTrip() {
        XCTAssertEqual(RoleSessionScope(stored: RoleSessionScope.groups.stored), .groups)
        XCTAssertEqual(RoleSessionScope(stored: RoleSessionScope.role("u-secretary").stored), .role("u-secretary"))
    }

    func testContextUsageDecodesAndFormatsPercent() throws {
        let raw = #"{"tokens":42500,"context_window":100000,"measured_at":"2026-11-05 01:00:00"}"#
        let usage = try JSONDecoder().decode(RoleChatContextUsage.self, from: Data(raw.utf8))
        XCTAssertEqual(usage.percent, 43)
        XCTAssertEqual(usage.label, "Контекст 43%")
    }

    func testContextUsageWithoutWindowHasNoLabel() {
        XCTAssertNil(RoleChatContextUsage(tokens: 10, contextWindow: 0).label)
    }
}
