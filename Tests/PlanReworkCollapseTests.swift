import XCTest
@testable import TaskFlow

/// Свёртка кругов доработки на данных реального плана «Рутины в TaskFlow»
/// (tcp_1cdc8fd2, 27.10.2026): 16 узлов, 23 связи, два круга доработки.
final class PlanReworkCollapseTests: XCTestCase {
    private typealias N = PlanReworkCollapse.Node
    private typealias E = PlanReworkCollapse.Edge

    private let nodes: [N] = [
        N(slotKey: "design", iteration: 0, reworkOfKey: nil),
        N(slotKey: "server", iteration: 0, reworkOfKey: nil),
        N(slotKey: "ios", iteration: 0, reworkOfKey: nil),
        N(slotKey: "ops", iteration: 0, reworkOfKey: nil),
        N(slotKey: "critic", iteration: 0, reworkOfKey: nil),
        N(slotKey: "qa", iteration: 0, reworkOfKey: nil),
        N(slotKey: "bf1s", iteration: 1, reworkOfKey: "server"),
        N(slotKey: "bf1i", iteration: 1, reworkOfKey: "ios"),
        N(slotKey: "if1", iteration: 1, reworkOfKey: "ops"),
        N(slotKey: "qa1", iteration: 1, reworkOfKey: "qa"),
        N(slotKey: "cr1", iteration: 1, reworkOfKey: "critic"),
        N(slotKey: "bf2s", iteration: 2, reworkOfKey: "bf1s"),
        N(slotKey: "bf2i", iteration: 2, reworkOfKey: "bf1i"),
        N(slotKey: "if2", iteration: 2, reworkOfKey: "if1"),
        N(slotKey: "qa2", iteration: 2, reworkOfKey: "qa1"),
        N(slotKey: "cr2", iteration: 2, reworkOfKey: "cr1"),
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
}
