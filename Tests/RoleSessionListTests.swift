import XCTest
@testable import TaskFlow

final class RoleSessionListTests: XCTestCase {
    private func item(_ id: String, others: [String], kind: String = "direct", room: String? = nil,
                      parent: String? = nil, project: String? = nil, last: String? = nil, branchOf: String? = nil) -> RoleSessionCandidate {
        RoleSessionCandidate(id: id, kind: kind, roomKind: room, parentChatID: parent, projectID: project,
                             otherMemberIDs: others, lastActivity: last, branchOfChatID: branchOf)
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
            item("topic", others: ["builder", "qa"], kind: "group", parent: "project", project: "p", last: "2026-11-06 01:00:00"),
            item("two", others: ["builder", "qa"], last: "2026-11-02 01:00:00"),
        ]
        XCTAssertEqual(RoleSessionList.select(list, scope: .groups), ["two", "old"])
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

    func testTopicsLiveInsideProjectNotInLists() {
        let list = [item("topic", others: ["a"], parent: "project", project: "p", last: "2026-11-05 01:00:00")]
        XCTAssertEqual(RoleSessionList.select(list, scope: .role("a")), [])
        XCTAssertEqual(RoleSessionList.select(list, scope: .groups), [])
    }

    func testBranchesFollowTheirParentAsTree() {
        let list = [
            item("root", others: ["a"], last: "2026-11-05 01:00:00"),
            item("newer", others: ["a"], last: "2026-11-05 03:00:00"),
            item("b1", others: ["a"], last: "2026-11-05 05:00:00", branchOf: "root"),
            item("b2", others: ["a"], last: "2026-11-05 04:00:00", branchOf: "root"),
            item("b11", others: ["a"], last: "2026-11-05 06:00:00", branchOf: "b1"),
        ]
        let rows = RoleSessionList.rows(list, scope: .role("a"))
        XCTAssertEqual(rows.map(\.id), ["newer", "root", "b1", "b11", "b2"])
        XCTAssertEqual(rows.map(\.lines), [
            [], [],
            [.branch],
            [.through, .lastBranch],
            [.lastBranch],
        ])
    }

    func testDeepRowUnderLastBranchHasNoThroughLine() {
        let list = [
            item("root", others: ["a"], last: "2026-11-05 01:00:00"),
            item("b", others: ["a"], last: "2026-11-05 02:00:00", branchOf: "root"),
            item("bb", others: ["a"], last: "2026-11-05 03:00:00", branchOf: "b"),
        ]
        XCTAssertEqual(RoleSessionList.rows(list, scope: .role("a")).last?.lines, [.blank, .lastBranch])
    }

    func testBranchWithoutVisibleParentIsARootRow() {
        let list = [item("orphan", others: ["a"], last: "2026-11-05 01:00:00", branchOf: "closed")]
        XCTAssertEqual(RoleSessionList.rows(list, scope: .role("a")).first?.lines, [])
    }

    func testProjectGroupResolvesFromGroupAndTopic() {
        XCTAssertEqual(RoleSessionList.projectGroupID(chatID: "g", parentChatID: nil, projectID: "p"), "g")
        XCTAssertEqual(RoleSessionList.projectGroupID(chatID: "t", parentChatID: "g", projectID: "p"), "g")
        XCTAssertNil(RoleSessionList.projectGroupID(chatID: "s", parentChatID: nil, projectID: nil))
    }

    func testOnlyNumberedSlotsOfTheRoleBecomeMentions() throws {
        let raw = #"""
        [{"subtask_id":"a","role_id":"role_builder","label":"Разработчик 1","state":"blocked"},
         {"subtask_id":"b","role_id":"role_builder","label":"Разработчик 2","state":null},
         {"subtask_id":"c","role_id":"role_qa","label":"Тестировщик","state":null}]
        """#
        let slots = try JSONDecoder().decode([RoleChatSlot].self, from: Data(raw.utf8))
        XCTAssertEqual(RoleChatSlot.numbered(for: "role_builder", in: slots).map(\.label), ["Разработчик 1", "Разработчик 2"])
        XCTAssertEqual(RoleChatSlot.numbered(for: "role_qa", in: slots), [])
        XCTAssertEqual(RoleChatSlot.numbered(for: "role_builder", in: nil), [])
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
