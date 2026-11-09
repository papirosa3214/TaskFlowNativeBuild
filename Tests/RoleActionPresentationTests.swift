import XCTest
@testable import TaskFlow
final class RoleActionPresentationTests: XCTestCase {
    private func step(_ tool: String, _ detail: String?, _ status: RoleChatLiveStep.Status = .done) -> RoleChatLiveStep {
        RoleChatLiveStep(id: "test", tool: tool, detail: detail, status: status)
    }
    func testDirectReadAndWriteAreDistinct() {
        XCTAssertEqual(RoleActionPresentation.forStep(step("read", "a.swift")).title, "Чтение")
        XCTAssertEqual(RoleActionPresentation.forStep(step("write", "a.swift")).title, "Запись")
        XCTAssertEqual(RoleActionPresentation.forStep(step("edit", "a.swift")).title, "Правка")
    }
    func testShellCategoriesAndCompoundCommandPreserveOneExecution() {
        for (command, label) in [("cat a.swift", "Чтение"), ("rg event Sources", "Поиск"), ("npm test", "Тесты"),
                                  ("xcodebuild build", "Сборка"), ("git diff", "Git"), ("cd repo && cat a && rg b Sources", "Чтение · Поиск")] {
            XCTAssertEqual(RoleActionPresentation.forStep(step("bash", command)).title, label, command)
        }
    }
    func testAmbiguousShellIsNotPresentedAsKnownAction() {
        for command in ["python3 run.py", "cat > output.txt", "cat <<'EOF'\ntext\nEOF", "echo $(cat secret)", "cat 'unfinished"] {
            XCTAssertEqual(RoleActionPresentation.forStep(step("bash", command)).title, "Команда")
        }
        XCTAssertEqual(RoleActionPresentation.forStep(step("bash", "rg 'cat a && git status' Sources")).title, "Поиск")
    }
    func testSkillReadUsesRealStatus() {
        let path = "~/taskflow/roles/designer/skills/user-research/SKILL.md"
        XCTAssertEqual(RoleActionPresentation.forStep(step("read", path)).title, "Навык подключён")
        XCTAssertEqual(RoleActionPresentation.forStep(step("read", path)).skillName, "user-research")
        XCTAssertEqual(RoleActionPresentation.forStep(step("read", path, .running)).title, "Подключение навыка")
        XCTAssertEqual(RoleActionPresentation.forStep(step("read", path, .error)).title, "Ошибка чтения навыка")
    }
    func testEndingAnimationDoesNotInventSuccessfulSkillRead() {
        let turn = RoleChatLiveTurn(chatID: "test", userID: "role", name: "Role", startedAt: nil,
            items: [.step(step("read", "/skills/user-research/SKILL.md", .running))], thinking: nil)
        guard case .step(let ended) = turn.ending().items[0] else { return XCTFail("missing step") }
        XCTAssertFalse(ended.resultReceived)
        XCTAssertEqual(RoleActionPresentation.forStep(ended).title, "Чтение навыка не подтверждено")
    }

    func testMentionWritingAndBashDoNotProveSkillWasLoaded() {
        let path = "~/taskflow/roles/designer/skills/user-research/SKILL.md"
        for tool in ["write", "edit", "bash", "grep"] {
            XCTAssertNil(RoleActionPresentation.forStep(step(tool, path)).skillName)
        }
        XCTAssertNil(RoleActionPresentation.forStep(step("read", "SKILL.md")).skillName)
        XCTAssertNil(RoleActionPresentation.forStep(step("read", "/skills/user-research/SKILL.md…")).skillName)
    }
    func testKnowledgeAndTrackerRemainDistinct() {
        XCTAssertEqual(RoleActionPresentation.forTool("taskflow_kb_search").title, "База знаний")
        XCTAssertEqual(RoleActionPresentation.forTool("taskflow_recall").title, "Поиск в памяти Mnemosyne")
        XCTAssertEqual(RoleActionPresentation.forTool("mcp__taskflow__recall").title, "Поиск в памяти Mnemosyne")
        XCTAssertEqual(RoleActionPresentation.forTool("taskflow_remember").title, "Память")
        XCTAssertEqual(RoleActionPresentation.forTool("taskflow_doc_read").title, "Документация")
        XCTAssertEqual(RoleActionPresentation.forTool("taskflow_taskflow_agents").title, "Трекер")
    }
    func testTraceArchiveKeepsDetailAndDecodesOlderSpans() throws {
        let old = Data(#"{"id":"old","label":"read","start":0,"status":"done","isEvent":false}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(AgentTraceSpan.self, from: old).detail)
        let span = AgentTraceSpan(id: "new", label: "read", start: .now, status: "done", detail: "/skills/user-research/SKILL.md")
        XCTAssertEqual(try JSONDecoder().decode(AgentTraceSpan.self, from: JSONEncoder().encode(span)).detail, span.detail)
    }
}
