import XCTest
@testable import TaskFlow

/// Свёртка кругов доработки на данных реального плана «Рутины в TaskFlow»
/// (tcp_1cdc8fd2, 27.10.2026): 16 узлов, 23 связи, два круга доработки.
final class PlanReworkCollapseTests: XCTestCase {
    private typealias N = PlanReworkCollapse.Node
    private typealias E = PlanReworkCollapse.Edge

    private let nodes: [N] = [
        N(slotKey: "design", iteration: 0, reworkOfKey: nil, roleKey: "design"),
        N(slotKey: "server", iteration: 0, reworkOfKey: nil, roleKey: "server"),
        N(slotKey: "ios", iteration: 0, reworkOfKey: nil, roleKey: "ios"),
        N(slotKey: "ops", iteration: 0, reworkOfKey: nil, roleKey: "ops"),
        N(slotKey: "critic", iteration: 0, reworkOfKey: nil, roleKey: "critic"),
        N(slotKey: "qa", iteration: 0, reworkOfKey: nil, roleKey: "qa"),
        N(slotKey: "bf1s", iteration: 1, reworkOfKey: "server", roleKey: "server"),
        N(slotKey: "bf1i", iteration: 1, reworkOfKey: "ios", roleKey: "ios"),
        N(slotKey: "if1", iteration: 1, reworkOfKey: "ops", roleKey: "ops"),
        N(slotKey: "qa1", iteration: 1, reworkOfKey: "qa", roleKey: "qa"),
        N(slotKey: "cr1", iteration: 1, reworkOfKey: "critic", roleKey: "critic"),
        N(slotKey: "bf2s", iteration: 2, reworkOfKey: "bf1s", roleKey: "server"),
        N(slotKey: "bf2i", iteration: 2, reworkOfKey: "bf1i", roleKey: "ios"),
        N(slotKey: "if2", iteration: 2, reworkOfKey: "if1", roleKey: "ops"),
        N(slotKey: "qa2", iteration: 2, reworkOfKey: "qa1", roleKey: "qa"),
        N(slotKey: "cr2", iteration: 2, reworkOfKey: "cr1", roleKey: "critic"),
    ]

    private let edges: [E] = [
        E(from: "design", to: "server"), E(from: "design", to: "ios"), E(from: "server", to: "ios"),
        E(from: "server", to: "ops"), E(from: "server", to: "critic"), E(from: "ios", to: "qa"),
        E(from: "ops", to: "qa"), E(from: "critic", to: "bf1s"), E(from: "design", to: "bf1s"),
        E(from: "design", to: "bf1i"), E(from: "bf1s", to: "bf1i"), E(from: "bf1s", to: "if1"),
        E(from: "bf1i", to: "qa1"), E(from: "if1", to: "qa1"), E(from: "qa1", to: "cr1"),
        E(from: "cr1", to: "bf2s"), E(from: "design", to: "bf2s"), E(from: "design", to: "bf2i"),
        E(from: "bf2s", to: "bf2i"), E(from: "bf2s", to: "if2"), E(from: "bf2i", to: "qa2"),
        E(from: "if2", to: "qa2"), E(from: "qa2", to: "cr2"),
    ]

    func testEachExecutorKeepsOnePlace() {
        let result = PlanReworkCollapse.collapse(nodes: nodes, edges: edges, limitExhausted: false)
        XCTAssertEqual(result.slots, ["design", "server", "ios", "ops", "critic", "qa"])
        XCTAssertEqual(result.latest["server"], "bf2s")
        XCTAssertEqual(result.latest["critic"], "cr2")
        XCTAssertEqual(result.latest["design"], "design")
    }

    func testReturnGoesFromReviewerToExecutorWithRoundColor() {
        let result = PlanReworkCollapse.collapse(nodes: nodes, edges: edges, limitExhausted: false)
        XCTAssertEqual(result.returns, [.init(from: "critic", to: "server", round: 2)])
        // Возврат не попадает в обычные связи, повторов и петель нет.
        XCTAssertFalse(result.edges.contains(E(from: "critic", to: "server")))
        XCTAssertEqual(Set(result.edges).count, result.edges.count)
        XCTAssertTrue(result.edges.allSatisfy { $0.from != $0.to })
        XCTAssertTrue(result.edges.contains(E(from: "qa", to: "critic")))
    }

    func testThirdRefusalTurnsReturnRed() {
        let result = PlanReworkCollapse.collapse(nodes: nodes, edges: edges, limitExhausted: true)
        XCTAssertEqual(result.returns, [.init(from: "critic", to: "server", round: 3)])
    }

    func testFirstRoundIsYellow() {
        let firstRound = nodes.filter { $0.iteration < 2 }
        let keys = Set(firstRound.map(\.slotKey))
        let result = PlanReworkCollapse.collapse(
            nodes: firstRound,
            edges: edges.filter { keys.contains($0.from) && keys.contains($0.to) },
            limitExhausted: false
        )
        XCTAssertEqual(result.returns.map(\.round), [1])
    }
    // Regression: server op rework links a builder fix to its QA source.
    // It is a new executor slot, not another attempt of that QA slot.
    private var mixedNodes: [N] {
        [N(slotKey: "builder_1", iteration: 0, reworkOfKey: nil, roleKey: "builder"),
         N(slotKey: "builder_2", iteration: 0, reworkOfKey: nil, roleKey: "builder"),
         N(slotKey: "qa_6", iteration: 0, reworkOfKey: nil, roleKey: "qa"),
         N(slotKey: "critic", iteration: 0, reworkOfKey: nil, roleKey: "critic_verifier"),
         N(slotKey: "qa_fix", iteration: 1, reworkOfKey: "qa_6", roleKey: "qa"),
         N(slotKey: "critic_recheck", iteration: 1, reworkOfKey: "critic", roleKey: "critic_verifier"),
         N(slotKey: "builder_fix", iteration: 2, reworkOfKey: "qa_fix", roleKey: "builder"),
         N(slotKey: "qa_recheck", iteration: 2, reworkOfKey: "qa_fix", roleKey: "qa")]
    }

    private var mixedEdges: [E] {
        [E(from: "builder_1", to: "qa_6"), E(from: "builder_2", to: "qa_6"),
         E(from: "qa_6", to: "critic"), E(from: "critic", to: "qa_fix"),
         E(from: "qa_fix", to: "builder_fix"), E(from: "builder_fix", to: "qa_recheck"),
         E(from: "qa_recheck", to: "critic_recheck")]
    }

    func testCrossRoleFixKeepsItsOwnSlotAndBothReturns() {
        let r = PlanReworkCollapse.collapse(nodes: mixedNodes, edges: mixedEdges, limitExhausted: false)
        XCTAssertTrue(r.slots.contains("builder_fix"))
        XCTAssertEqual(r.latest["qa_6"], "qa_recheck")
        XCTAssertEqual(r.latest["builder_fix"], "builder_fix")
        XCTAssertEqual(Set(r.returns), [.init(from: "critic", to: "qa_6", round: 1),
                                      .init(from: "qa_6", to: "builder_fix", round: 2)])
        XCTAssertFalse(r.edges.contains(E(from: "qa_6", to: "builder_fix")))
        XCTAssertTrue(r.edges.contains(E(from: "builder_fix", to: "qa_6")))
    }

    func testSameRoleExecutorsAreMatchedByExactSlotAcrossInputOrder() {
        let ns = mixedNodes + [N(slotKey: "builder_2_fix", iteration: 1, reworkOfKey: "builder_2", roleKey: "builder")]
        let es = mixedEdges + [E(from: "critic", to: "builder_2_fix")]
        for input in [ns, Array(ns.reversed())] {
            let r = PlanReworkCollapse.collapse(nodes: input, edges: es, limitExhausted: false)
            XCTAssertEqual(r.latest["builder_1"], "builder_1")
            XCTAssertEqual(r.latest["builder_2"], "builder_2_fix")
            XCTAssertEqual(r.latest["qa_6"], "qa_recheck")
            XCTAssertTrue(r.returns.contains(.init(from: "critic", to: "builder_2", round: 1)))
            XCTAssertTrue(r.returns.contains(.init(from: "qa_6", to: "builder_fix", round: 2)))
        }
    }

    // SSH snapshot: tcp_e2e17022 version 4, 29.10.2026, five builder slots.
    func testInfraPanelVersion4KeepsActualTargets() {
        let ns: [N] = [
            N(slotKey: "builder_1", iteration: 0, reworkOfKey: nil, roleKey: "builder"),
            N(slotKey: "builder_2", iteration: 0, reworkOfKey: nil, roleKey: "builder"),
            N(slotKey: "builder_3", iteration: 0, reworkOfKey: nil, roleKey: "builder"),
            N(slotKey: "builder_4", iteration: 0, reworkOfKey: nil, roleKey: "builder"),
            N(slotKey: "builder_5", iteration: 0, reworkOfKey: nil, roleKey: "builder"),
            N(slotKey: "qa_6", iteration: 0, reworkOfKey: nil, roleKey: "qa"),
            N(slotKey: "final_review_0c057925", iteration: 0, reworkOfKey: nil, roleKey: "critic_verifier"),
            N(slotKey: "qa_fix_3c91f1fd", iteration: 1, reworkOfKey: "qa_6", roleKey: "qa"),
            N(slotKey: "critic_recheck_f8f46b92", iteration: 1, reworkOfKey: "final_review_0c057925", roleKey: "critic_verifier"),
            N(slotKey: "builder_fix_2", iteration: 2, reworkOfKey: "qa_fix_3c91f1fd", roleKey: "builder"),
            N(slotKey: "qa_recheck_2", iteration: 2, reworkOfKey: "qa_fix_3c91f1fd", roleKey: "qa")
        ]
        let es: [E] = [
            E(from: "builder_1", to: "builder_4"),
            E(from: "builder_2", to: "builder_3"),
            E(from: "builder_3", to: "builder_1"),
            E(from: "builder_4", to: "qa_6"),
            E(from: "builder_4", to: "qa_fix_3c91f1fd"),
            E(from: "builder_5", to: "qa_6"),
            E(from: "builder_5", to: "qa_fix_3c91f1fd"),
            E(from: "builder_fix_2", to: "qa_recheck_2"),
            E(from: "final_review_0c057925", to: "qa_fix_3c91f1fd"),
            E(from: "qa_6", to: "final_review_0c057925"),
            E(from: "qa_fix_3c91f1fd", to: "builder_fix_2"),
            E(from: "qa_recheck_2", to: "critic_recheck_f8f46b92")
        ]
        let r = PlanReworkCollapse.collapse(nodes: ns, edges: es, limitExhausted: false)
        XCTAssertEqual(r.slots.count, 8)
        XCTAssertEqual(r.latest["qa_6"], "qa_recheck_2")
        XCTAssertEqual(r.latest["builder_fix_2"], "builder_fix_2")
        for slot in ["builder_1", "builder_2", "builder_3", "builder_4", "builder_5"] {
            XCTAssertEqual(r.latest[slot], slot)
        }
        XCTAssertEqual(Set(r.returns), [.init(from: "final_review_0c057925", to: "qa_6", round: 1),
                                      .init(from: "qa_6", to: "builder_fix_2", round: 2)])
    }

}
