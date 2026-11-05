import XCTest
@testable import TaskFlow

/// Полотно «Координации»: уровни этапов, видимые связи и то, какую правку плана
/// собирает каждый плюс. Чистая логика, симулятор не нужен.
final class CoordinationBoardTests: XCTestCase {
    private func node(_ slot: String, role: String = "builder", skipped: Bool = false) -> ApiCollaborationPlanNode {
        ApiCollaborationPlanNode(
            slotKey: slot, roleKey: role, required: true, expectedResult: "Результат \(slot)",
            instructions: nil, origin: nil, addedBy: nil, addedReason: nil, iteration: nil, reworkOfKey: nil,
            skippedAt: skipped ? "2026-11-05" : nil, skipReason: nil, taskId: nil, taskTitle: nil, executionState: nil,
            sourcePlanStatus: nil, sourcePlanVersion: nil, sourcePlanId: nil, sourceSlotKey: nil, sourceSubtaskId: nil,
            workChoice: nil, originalTitle: nil, plannedWork: nil, requiresChoice: nil, responsible: nil, waitingFor: nil,
            resultDocument: nil, submissionReceipt: nil
        )
    }

    private func edge(_ from: String, _ to: String) -> ApiCollaborationPlanEdge {
        ApiCollaborationPlanEdge(fromSlotKey: from, toSlotKey: to, startCondition: "submitted")
    }

    private func plan(_ nodes: [ApiCollaborationPlanNode], _ edges: [ApiCollaborationPlanEdge] = [],
                      profile: String = "delivery") -> ApiCollaborationPlan {
        ApiCollaborationPlan(id: "p", taskId: "t", revision: 1, status: "approved", profile: profile, rationale: "",
                             nodes: nodes, edges: edges, version: 1, pendingProposals: nil,
                             branchSnapshot: nil, branchRootTaskId: nil)
    }

    /// a → (b, c) → d: классический ромб из параллельных этапов.
    private var diamond: ApiCollaborationPlan {
        plan([node("a"), node("b"), node("c"), node("d")],
             [edge("a", "b"), edge("a", "c"), edge("b", "d"), edge("c", "d")])
    }

    // MARK: - Какая кнопка на карточке

    func testOrchestratedProfileOpensMissionControl() {
        let solo = plan([node("orchestrate", role: "code_orchestrator"), node("assemble", role: "code_orchestrator")],
                        profile: "orchestrated")
        XCTAssertTrue(CoordinationBoard.isOrchestratorOnly(solo))
    }

    func testOrchestratorProfileStaysMissionControlAfterHeHiredRoles() {
        let grown = plan([node("orchestrate", role: "code_orchestrator"), node("work", role: "builder")],
                         profile: "orchestrated")
        XCTAssertTrue(CoordinationBoard.isOrchestratorOnly(grown))
    }

    func testPlanWhereOnlyTheOrchestratorWorksOpensMissionControl() {
        let solo = plan([node("orchestrate", role: "code_orchestrator")], profile: "single_executor")
        XCTAssertTrue(CoordinationBoard.isOrchestratorOnly(solo))
    }

    func testTeamPlanOpensCoordination() {
        XCTAssertFalse(CoordinationBoard.isOrchestratorOnly(diamond))
        let withOrchestrator = plan([node("orchestrate", role: "code_orchestrator"), node("work", role: "builder")])
        XCTAssertFalse(CoordinationBoard.isOrchestratorOnly(withOrchestrator))
    }

    func testEmptyPlanIsNotOrchestratorOnly() {
        XCTAssertFalse(CoordinationBoard.isOrchestratorOnly(plan([])))
    }

    // MARK: - Уровни и связи

    func testParallelStagesShareALevel() {
        XCTAssertEqual(CoordinationBoard.levels(of: diamond), [["a"], ["b", "c"], ["d"]])
    }

    func testStageSitsBelowItsLongestChain() {
        let uneven = plan([node("a"), node("b"), node("c")], [edge("a", "b"), edge("b", "c"), edge("a", "c")])
        XCTAssertEqual(CoordinationBoard.levels(of: uneven), [["a"], ["b"], ["c"]])
    }

    func testUnrelatedChainsStartOnTheFirstLevel() {
        let chains = plan([node("a"), node("b"), node("x")], [edge("a", "b")])
        XCTAssertEqual(CoordinationBoard.levels(of: chains), [["a", "x"], ["b"]])
    }

    func testBrokenCycleStillShowsEveryStage() {
        let loop = plan([node("a"), node("b")], [edge("a", "b"), edge("b", "a")])
        XCTAssertEqual(Set(CoordinationBoard.levels(of: loop).flatMap { $0 }), ["a", "b"])
    }

    func testRedundantLinkIsHiddenAfterInsertion() {
        // Вставка x между a и b оставляет на сервере и a → b: рисовать её незачем.
        let inserted = plan([node("a"), node("x"), node("b")], [edge("a", "b"), edge("a", "x"), edge("x", "b")])
        let links = CoordinationBoard.visibleLinks(of: inserted)
        XCTAssertEqual(links.map(\.from), ["a", "x"])
        XCTAssertEqual(links.map(\.to), ["x", "b"])
    }

    // MARK: - Что собирает каждый плюс

    func testPlusOnLinkInsertsBetween() {
        let preset = CoordinationBoard.insert(between: "a", and: "b")
        XCTAssertEqual(preset.after, ["a"])
        XCTAssertEqual(preset.before, ["b"])
    }

    func testPlusBesideLevelWaitsForTheSameAndHoldsOnlyNotStartedNext() {
        let preset = CoordinationBoard.beside(level: ["b", "c"], in: diamond, pending: ["d"])
        XCTAssertEqual(preset.after, ["a"])
        XCTAssertEqual(preset.before, ["d"])
        let started = CoordinationBoard.beside(level: ["b", "c"], in: diamond, pending: [])
        XCTAssertEqual(started.before, [], "начатый этап нельзя заставить ждать новый")
    }

    func testPlusBesideFirstLevelStartsANewChainAtOnce() {
        let preset = CoordinationBoard.beside(level: ["a"], in: diamond, pending: [])
        XCTAssertEqual(preset.after, [])
    }

    func testPlusAtTheEndWaitsForTheLastStages() {
        XCTAssertEqual(CoordinationBoard.atEnd(of: diamond).after, ["d"])
        let chains = plan([node("a"), node("b")])
        XCTAssertEqual(CoordinationBoard.atEnd(of: chains).after, ["a", "b"])
    }

    func testSkippedStageIsNotWaitedForAtTheEnd() {
        let withSkipped = plan([node("a"), node("b", skipped: true)], [edge("a", "b")])
        XCTAssertEqual(CoordinationBoard.atEnd(of: withSkipped).after, ["a"])
    }

    func testSplitKeepsTheRolePlaceAndNotStartedNext() {
        let preset = CoordinationBoard.split(node("b", role: "designer"), in: diamond, pending: ["d"])
        XCTAssertEqual(preset.roleKey, "designer")
        XCTAssertEqual(preset.after, ["a"])
        XCTAssertEqual(preset.before, ["d"])
    }

    func testAppendedTaskKeepsWhatWasWritten() {
        XCTAssertEqual(CoordinationBoard.appended("  ещё кусок ", to: "Сделать экран"), "Сделать экран\n\nещё кусок")
        XCTAssertEqual(CoordinationBoard.appended("кусок", to: nil), "кусок")
        XCTAssertEqual(CoordinationBoard.appended("кусок", to: "  "), "кусок")
    }

    func testBoardStopsGrowingAtServerLimit() {
        let full = plan((0..<16).map { node("s\($0)") })
        XCTAssertFalse(CoordinationBoard.canGrow(full))
        XCTAssertTrue(CoordinationBoard.canGrow(diamond))
    }

    // MARK: - Раскладка

    private let metrics = CoordinationBoard.Metrics(cardWidth: 100, cardHeight: 50, columnGap: 10, levelGap: 40, plusSize: 30)

    func testLayoutPlacesLevelsTopDownAndParallelSideBySide() {
        let layout = CoordinationBoard.layout(levels: [["a"], ["b", "c"], ["d"]], metrics: metrics, editable: false, minWidth: 0)
        XCTAssertEqual(layout.size.width, 210, accuracy: 0.5)
        XCTAssertEqual(layout.size.height, 230, accuracy: 0.5)
        XCTAssertEqual(layout.centers["b"]?.x ?? 0, 50, accuracy: 0.5)
        XCTAssertEqual(layout.centers["c"]?.x ?? 0, 160, accuracy: 0.5)
        XCTAssertEqual(layout.centers["a"]?.x ?? 0, 105, accuracy: 0.5)
        XCTAssertEqual(layout.centers["d"]?.y ?? 0, 205, accuracy: 0.5)
    }

    func testEditableLayoutMakesRoomForPluses() {
        let layout = CoordinationBoard.layout(levels: [["a"], ["b", "c"]], metrics: metrics, editable: true, minWidth: 0)
        XCTAssertEqual(layout.besidePlus.count, 2)
        XCTAssertNotNil(layout.endPlus)
        let c = layout.centers["c"]!
        let plus = layout.besidePlus[1]
        XCTAssertGreaterThan(plus.x - 15, c.x + 50, "боковой плюс не наезжает на карточку")
        XCTAssertGreaterThanOrEqual(layout.size.width, plus.x + 15)
        XCTAssertGreaterThanOrEqual(layout.size.height, layout.endPlus!.y + 15)
    }

    func testLayoutCentersOnWideScreen() {
        let layout = CoordinationBoard.layout(levels: [["a"]], metrics: metrics, editable: false, minWidth: 400)
        XCTAssertEqual(layout.size.width, 400, accuracy: 0.5)
        XCTAssertEqual(layout.centers["a"]?.x ?? 0, 200, accuracy: 0.5)
    }
}
