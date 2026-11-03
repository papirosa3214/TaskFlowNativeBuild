import XCTest
@testable import TaskFlow

/// Движок режима подсказок (LOCK-HINTS-ONBOARDING-20261016).
@MainActor
final class HintCenterTests: XCTestCase {
    func testVoiceModesHintCompletes() {
        let name = "voice-modes-hint-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.voiceModes])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.voiceModes, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(center.currentScenario?.id, "voice-modes")
        center.next()
        XCTAssertTrue(center.completed.contains("voice-modes"))
        XCTAssertNil(center.active)
    }

    func testInboxHintCompletes() {
        let name = "inbox-hint-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.inboxTickets])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.inboxTickets, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(center.currentScenario?.id, "inbox-tickets")
        center.next()
        XCTAssertTrue(center.completed.contains("inbox-tickets"))
        XCTAssertNil(center.active)
    }
    func testAllTasksHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "projects-all-tasks" })
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, "projects.all-tasks")
        center.next()
        XCTAssertEqual(center.currentStep?.anchor, "all-tasks.filter")
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testAssistantSessionHintCompletes() {
        let scenario = HintScenarios.assistantSession
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.chatSession)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testRoutineEditingHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "routine-editing" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.routineInstructions)
        center.next()
        XCTAssertEqual(center.currentStep?.anchor, "routine.planTemplate")
        center.next()
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.routineHistory)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testOwnMessageActionsHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "chat-own-message-copy" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.chatOwnMessageCopy)
        XCTAssertTrue(center.currentStep?.text.contains("Убрать сообщение") == true)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testDiscussionDeliveryHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "chat-discussion-delivery" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.active?.step, "status")
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.chatDiscussionDelivery)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }


    func testAgentPromptSettingsHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "agent-prompt-settings" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.isEnabled = true
        center.report(anchor: "team.agent-instructions", frame: frame)
        XCTAssertEqual(center.active?.step, "common")
        center.next()
        XCTAssertTrue(center.completed.contains("agent-prompt-settings"))
    }

    func testChatComposerStyleHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "chat-composer-style" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.chatComposerStyle)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testRoleSessionHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "role-session" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.chatSession)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testChatRoleStartHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "chat-role-start" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.chatRoleStart)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testChatComposerControlsHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "chat-composer-controls" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, "chat.composer.actions")
        center.next()
        XCTAssertEqual(center.currentStep?.anchor, "chat.context-window")
        center.next()
        XCTAssertEqual(center.active?.step, "commands")
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    func testTaskCoordinationHintCompletes() throws {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.taskCoordination])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.taskCoordination, frame: frame)
        XCTAssertEqual(center.active?.step, "step")
        // Второй шаг (02.11.2026) — контракт миссии: он лежит в этом же
        // экране и объясняет, почему шаг может не закрыться.
        center.next()
        XCTAssertEqual(center.active?.step, "mission")
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.missionControl)
        center.next()
        XCTAssertTrue(center.completed.contains("task-coordination"))
    }

    /// Контракт миссии (02.11.2026): новая функция — новая подсказка.
    func testMissionControlHintWalksCoordinationToScreen() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "mission-control" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.taskCoordination, frame: frame)
        XCTAssertEqual(center.active?.step, "coordination")
        center.next()
        XCTAssertEqual(center.active?.step, "mission")
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.missionControl)
        center.next()
        XCTAssertEqual(center.active?.step, "screen")
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.missionControlScreen)
        center.next()
        XCTAssertTrue(center.completed.contains("mission-control"))
    }

    /// Схема подсказок: у каждого сценария есть стартовый шаг, а каждый
    /// переход ведёт в существующий шаг. Сломанная ссылка — это сценарий,
    /// который молча не доходит до конца.
    func testAllScenariosHaveValidStepsAndTransitions() {
        for scenario in HintScenarios.all {
            XCTAssertFalse(scenario.steps.isEmpty, "\(scenario.id): нет шагов")
            XCTAssertNotNil(scenario.steps[scenario.start], "\(scenario.id): стартовый шаг «\(scenario.start)» не найден")
            for (key, step) in scenario.steps {
                if let next = step.next {
                    XCTAssertNotNil(scenario.steps[next], "\(scenario.id): шаг «\(key)» ведёт в несуществующий «\(next)»")
                }
                for branch in step.branches {
                    if let next = branch.next {
                        XCTAssertNotNil(scenario.steps[next], "\(scenario.id): ветка «\(branch.title)» ведёт в несуществующий «\(next)»")
                    }
                }
            }
        }
    }

    /// Идентификаторы сценариев не должны повторяться: список в настройках
    /// показывает каждый сценарий один раз, а «Пройти заново» ищет по id.
    func testScenarioIdsAreUnique() {
        let ids = HintScenarios.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "повторяющиеся id сценариев")
    }

    func testChatItemBudgetHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "chat-item-budget" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.isEnabled = true
        center.report(anchor: "server.setting.chat_item_max_actions", frame: frame)
        XCTAssertEqual(center.active?.step, "limit")
        XCTAssertTrue(center.currentStep?.text.contains("пункт") == true)
        center.next()
        XCTAssertTrue(center.completed.contains("chat-item-budget"))
    }

    func testChatConveyorHintsComplete() throws {
        for (id, anchor, step) in [
            ("chat-work-plan", "chat.work-plan", "plan"),
            ("chat-delivery-badge", "chat.delivery-badge", "delivery"),
        ] {
            let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == id })
            let center = HintCenter(defaults: defaults, scenarios: [scenario])
            center.isEnabled = true
            center.report(anchor: anchor, frame: frame)
            XCTAssertEqual(center.active?.step, step)
            center.next()
            XCTAssertTrue(center.completed.contains(id))
        }
    }

    func testOwnMessageCopyHintCompletes() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "chat-own-message-copy" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.isEnabled = true
        center.report(anchor: "chat.own-message.copy", frame: frame)
        XCTAssertEqual(center.active?.step, "copy")
        // С 26.10.2026 отдельной иконки копирования под своим сообщением
        // нет: действия открываются долгим нажатием (docs/2026-10-26-chat-withdrawal.md).
        XCTAssertEqual(center.currentStep?.title, "Долгое нажатие на сообщение")
        XCTAssertTrue(center.currentStep?.text.contains("скопировать текст") == true)
        center.next()
        XCTAssertTrue(center.completed.contains("chat-own-message-copy"))
    }

    /// Уточнение роли у владельца (26.10.2026): подсказка ведёт к форме
    /// ответа под сообщением роли.
    func testChatQuestionHintCompletes() {
        let scenario = HintScenarios.chatQuestion
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.chatQuestion, frame: frame)
        XCTAssertEqual(center.active?.step, "answer")
        XCTAssertEqual(scenario.steps["answer"]?.anchor, HintAnchorID.chatQuestion)
        XCTAssertTrue(center.currentStep?.text.contains("Свой вариант") == true)
        center.next()
        XCTAssertTrue(center.completed.contains("chat-question"))
    }

    func testUnifiedPlannerHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.unifiedPlanner])
        center.start("unified-planner")
        XCTAssertEqual(center.active?.step, "list")
        center.next()
        XCTAssertTrue(center.completed.contains("unified-planner"))
    }

    func testAIUsageHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.aiUsage])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.aiUsage, frame: frame)
        XCTAssertEqual(center.active?.step, "usage")
        center.next()
        XCTAssertTrue(center.completed.contains("ai-usage"))
    }

    func testRoleLoadCollapseHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.roleLoadRows])
        center.start("role-load-rows")
        XCTAssertEqual(center.active?.step, "collapse")
        XCTAssertEqual(HintScenarios.roleLoadRows.steps["collapse"]?.anchor, HintAnchorID.roleLoadRows)
        center.next()
        XCTAssertTrue(center.completed.contains("role-load-rows"))
    }
    func testRoleBehaviorHintExplainsSaveAndApplySeparately() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.roleBehavior])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.roleBehavior, frame: frame)
        XCTAssertEqual(center.active?.step, "templates")
        XCTAssertTrue(center.currentStep?.text.contains("Сохранить шаблон") == true)
        XCTAssertTrue(center.currentStep?.text.contains("Применить личность") == true)
        center.next()
        XCTAssertTrue(center.completed.contains("role-behavior"))
    }
    func testChatExecutionModeHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.chatExecutionMode])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.chatExecutionMode, frame: frame)
        XCTAssertEqual(center.active?.step, "choose")
        center.next()
        XCTAssertTrue(center.completed.contains("chat-execution-mode"))
    }
    func testNoteMarkdownEditingHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.noteMarkdownEditing])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.noteMarkdownEditing, frame: frame)
        XCTAssertEqual(center.active?.step, "edit")
        center.next()
        XCTAssertTrue(center.completed.contains("note-markdown-editing"))
    }
    func testVoiceScreenShareHintRequiresSystemStart() throws {
        let scenario = try XCTUnwrap(HintScenarios.all.first { $0.id == "voice-screen-share" })
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        XCTAssertEqual(center.currentStep?.anchor, "voice.screen-share")
        XCTAssertTrue(center.currentStep?.text.contains("Начать трансляцию") == true)
        center.next()
        XCTAssertTrue(center.completed.contains(scenario.id))
    }

    private var defaults: UserDefaults!
    private let frame = CGRect(x: 10, y: 10, width: 40, height: 40)

    func testVoiceHintExplainsMinimizeAndCompletesAtMiniPlayer() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.voiceConversation])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.voiceMinimize, frame: frame)
        XCTAssertEqual(center.active?.step, "minimize")
        center.tapped(anchor: HintAnchorID.voiceMinimize)
        center.report(anchor: HintAnchorID.voiceMiniPlayer, frame: frame)
        XCTAssertEqual(center.active?.step, "mini")
        center.next()
        XCTAssertTrue(center.completed.contains("voice-conversation"))
    }

    override func setUp() {
        defaults = UserDefaults(suiteName: "hints-test-\(UUID().uuidString)")
    }

    func testExternalAppsHintCompletesAndLinksDocumentation() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.externalApps])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.roleExternalApps, frame: frame)
        XCTAssertEqual(center.active?.step, "access")
        XCTAssertEqual(center.currentStep?.documentationResource, "2026-10-18-role-external-apps")
        center.next()
        XCTAssertTrue(center.completed.contains("external-apps"))
    }

    private func makeCenter() -> HintCenter { HintCenter(defaults: defaults, scenarios: [HintScenarios.taskPlan]) }

    func testSystemSummaryHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.systemSummary])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.systemSummary, frame: frame)
        XCTAssertEqual(center.active?.step, "summary")
        center.next()
        // Второй шаг — «Как читать сводку»: он объясняет новый смысл корзин
        // после правки 16.10.2026 (владелец может не заметить изменения).
        XCTAssertEqual(center.active?.step, "reading")
        XCTAssertFalse(center.completed.contains("system-summary"))
        center.next()
        XCTAssertTrue(center.completed.contains("system-summary"))
    }

    /// Второй шаг сводки обязан объяснять, чем «Тревоги» отличаются от
    /// «Поломок» — иначе новое поведение нечем узнать.
    func testSystemSummaryExplainsWarningBucketMeaning() {
        let step = HintScenarios.systemSummary.steps["reading"]
        XCTAssertEqual(step?.anchor, HintAnchorID.systemSummary)
        let text = try? XCTUnwrap(step?.text)
        XCTAssertTrue(text?.contains("Тревоги") ?? false)
        XCTAssertTrue(text?.contains("формально") ?? false)
        XCTAssertTrue(text?.contains("подробности не пришли") ?? false)
    }

    func testContextAndUsageHintsComplete() {
        for scenario in [HintScenarios.contextObservability, HintScenarios.jevUsage] {
            let center = HintCenter(defaults: defaults, scenarios: [scenario])
            center.isEnabled = true
            let anchor = scenario.id == "jev-usage" ? HintAnchorID.jevUsage : HintAnchorID.contextObservability
            center.report(anchor: anchor, frame: frame)
            XCTAssertNotNil(center.active)
            center.next()
            XCTAssertTrue(center.completed.contains(scenario.id))
        }
    }

    func testJevHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.jev])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.jevConnection, frame: frame)
        XCTAssertEqual(center.active?.step, "connection")
        center.next()
        XCTAssertTrue(center.completed.contains("jev"))
    }

    func testMemoryObserverHintCompletes() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.memoryObserver])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.memoryObserver, frame: frame)
        XCTAssertEqual(center.active?.step, "screen")
        center.next()
        XCTAssertTrue(center.completed.contains("memory-observer"))
    }

    func testWebhookHintExplainsGenericReceiverAndOptionalCodexBranch() {
        let center = HintCenter(defaults: defaults, scenarios: [HintScenarios.webhooks])
        center.isEnabled = true
        center.report(anchor: HintAnchorID.webhooksEntry, frame: frame)
        XCTAssertEqual(center.active?.step, "entry")
        XCTAssertEqual(center.currentStep?.documentationResource, "2026-10-18-webhooks-integration")
        center.tapped(anchor: HintAnchorID.webhooksEntry)
        XCTAssertEqual(center.active?.step, "add")
        center.tapped(anchor: HintAnchorID.webhooksAdd)
        XCTAssertEqual(center.active?.step, "url")
        XCTAssertTrue(center.currentStep?.text.contains("HTTP(S)-адрес") == true)
        center.next()
        XCTAssertEqual(center.active?.step, "events")
        center.next()
        XCTAssertEqual(center.active?.step, "project")
        center.next()
        XCTAssertEqual(center.active?.step, "codex-choice")
        // Текст подсказки говорит «Codex не обязателен» (без «здесь»):
        // так он записан в сценарии с 20.10.2026.
        XCTAssertTrue(center.currentStep?.text.contains("Codex не обязателен") == true)
        XCTAssertTrue(center.currentStep?.text.contains("совместимым внешним приёмником") == true)
        XCTAssertTrue(center.currentStep?.text.contains("вручную очисти поле ID") == true)
        XCTAssertTrue(center.currentStep?.text.contains("Выбор шага сам поле не меняет") == true)
        let noCodex = try! XCTUnwrap(center.currentStep?.branches.first { $0.title == "Только HTTP-приёмник" })
        center.choose(noCodex)
        XCTAssertEqual(center.active?.step, "save")
        center.tapped(anchor: HintAnchorID.webhookSave)
        XCTAssertEqual(center.active?.step, "test")
        XCTAssertEqual(center.currentStep?.anchor, HintAnchorID.webhookTest)
        center.next()
        XCTAssertTrue(center.completed.contains("webhooks"))

        center.restart("webhooks")
        center.next()
        center.next()
        center.next()
        center.next()
        center.next()
        let useCodex = try! XCTUnwrap(center.currentStep?.branches.first { $0.title == "Ещё передавать в Codex" })
        center.choose(useCodex)
        XCTAssertEqual(center.active?.step, "codex")
        center.next()
        XCTAssertEqual(center.active?.step, "save")
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
