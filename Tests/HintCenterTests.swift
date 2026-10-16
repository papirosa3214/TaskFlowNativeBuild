import XCTest
@testable import TaskFlow

/// Движок режима подсказок (LOCK-HINTS-ONBOARDING-20261016).
@MainActor
final class HintCenterTests: XCTestCase {
    private var defaults: UserDefaults!
    private let frame = CGRect(x: 10, y: 10, width: 40, height: 40)

    override func setUp() {
        defaults = UserDefaults(suiteName: "hints-test-\(UUID().uuidString)")
    }

    private func makeCenter() -> HintCenter { HintCenter(defaults: defaults, scenarios: [HintScenarios.taskPlan]) }

    func testSystemSummaryHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.systemSummary])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.systemSummary, frame: frame)
        XCTAssertEqual(center.active?.step, "summary")
        center.next()
        XCTAssertTrue(center.completed.contains("system-summary"))
    }

    func testJevHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.jev])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.jevConnection, frame: frame)
        XCTAssertEqual(center.active?.step, "connection")
        center.next()
        XCTAssertTrue(center.completed.contains("jev"))
    }

    func testRoleActionHintCompletesWithoutChangingWork() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.roleActions])
        center.start("role-actions")
        XCTAssertEqual(center.active?.step, "actions")
        XCTAssertTrue(center.currentStep?.text.contains("Навык подключён") == true)
        center.next()
        XCTAssertNil(center.active)
    }

    func testDictationHintExplainsEditableDraft() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.chatDictation])
        center.start("chat-dictation")
        XCTAssertEqual(center.active?.step, "dictation")
        XCTAssertTrue(center.currentStep?.text.contains("поправить руками") == true)
        center.next()
        XCTAssertNil(center.active)
    }

    func testDisabledModeNeverStarts() {
        let center = makeCenter()
        center.report(anchor: HintAnchorID.taskWorkMenu, frame: frame)
        XCTAssertNil(center.currentStep)
    }

    func testStartsWhenFirstAnchorAppearsAndTapAdvances() {
        let center = makeCenter()
        center.isEnabled = true
        XCTAssertNil(center.currentStep, "без элемента на экране сценарий не начинается")
        center.report(anchor: HintAnchorID.taskWorkMenu, frame: frame)
        XCTAssertEqual(center.active?.step, "work-menu")
        center.tapped(anchor: HintAnchorID.taskWorkMenu)
        XCTAssertEqual(center.active?.step, "plan-source")
    }

    func testBranchesLeadToDifferentSteps() {
        let center = makeCenter()
        center.start("task-plan")
        center.next()
        let branches = try! XCTUnwrap(center.currentStep?.branches)
        center.choose(branches[0])
        XCTAssertEqual(center.active?.step, "from-subtasks")
        center.restart("task-plan")
        center.next()
        center.choose(center.currentStep!.branches[1])
        XCTAssertEqual(center.active?.step, "from-template")
    }

    func testFinishMarksCompletedAndPersists() {
        let center = makeCenter()
        center.start("task-plan")
        center.finish()
        XCTAssertNil(center.currentStep)
        XCTAssertTrue(center.completed.contains("task-plan"))
        let reopened = makeCenter()
        XCTAssertTrue(reopened.isEnabled)
        XCTAssertTrue(reopened.completed.contains("task-plan"))
        reopened.report(anchor: HintAnchorID.taskWorkMenu, frame: frame)
        XCTAssertNil(reopened.currentStep, "пройденный сценарий сам не начинается")
    }

    func testLastStepFinishesScenario() {
        let center = makeCenter()
        center.start("task-plan")
        center.next()
        center.choose(center.currentStep!.branches[1])
        center.next()
        XCTAssertEqual(center.active?.step, "steps")
        center.next()
        XCTAssertNil(center.currentStep)
        XCTAssertTrue(center.completed.contains("task-plan"))
    }

    func testTurningOffHidesHint() {
        let center = makeCenter()
        center.start("task-plan")
        center.isEnabled = false
        XCTAssertNil(center.currentStep)
    }
    func testLinkedTasksScenarioCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.taskLinks])
        center.isEnabled = true
        center.report(anchor: "task.section.linkedTasks", frame: frame)
        XCTAssertEqual(center.active?.step, "links")
        XCTAssertEqual(center.currentStep?.anchor, "task.section.linkedTasks")
        center.next()
        XCTAssertNil(center.currentStep)
        XCTAssertTrue(center.completed.contains("task-links"))
    }
    func testChatMembersScenarioCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.chatMembers])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.chatMembersMenu, frame: frame)
        XCTAssertEqual(center.active?.step, "members")
        center.next()
        XCTAssertTrue(center.completed.contains("chat-members"))
    }
}
