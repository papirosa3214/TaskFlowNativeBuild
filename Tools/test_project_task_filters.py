#!/usr/bin/env python3
"""Run production filter policy and hint flow on macOS; no simulator.
ApiTask fixture models only policy inputs, not the full REST decoder.
Before extraction the runner reads the original enum from ProjectTasksScreen.
"""
from pathlib import Path
import subprocess, tempfile, sys
root = Path(__file__).resolve().parents[1]
policy = root/'Sources/Features/Projects/ProjectTaskFilter.swift'
if "--legacy" in sys.argv:
    text = subprocess.check_output(["git", "show", "6a1a5e19cef081f834d16b68874fbf47cd4d73a9:Sources/Features/Projects/ProjectTasksScreen.swift"], cwd=root, text=True)
    source = text[text.index("enum ProjectTaskFilter:"):text.index("\nstruct ProjectTasksScreen:")]
elif policy.exists():
    source = policy.read_text()
else:
    text = (root/'Sources/Features/Projects/ProjectTasksScreen.swift').read_text()
    source = text[text.index('enum ProjectTaskFilter:'):text.index('\nstruct ProjectTasksScreen:')]
fixture = '''
import Foundation
import XCTest
enum TaskStatus: String, Decodable { case active, completed }
enum AgentState: String, Decodable { case inProgress = "in_progress", blocked, review, todo }
struct ApiTask: Decodable {
    let status: TaskStatus
    let agentState: AgentState?
    let branchAgentState: AgentState?
    let assigneeId: String?
    let archivedAt: String?
    var isArchived: Bool { archivedAt != nil }
    var listAgentState: AgentState? { agentState ?? branchAgentState }
    enum CodingKeys: String, CodingKey {
        case status, agentState = "agent_state", branchAgentState = "branch_agent_state", assigneeId = "assignee_id"
        case archivedAt = "archived_at"
    }
}
'''
tests = (root/'Tests/ProjectTaskFilterTests.swift').read_text().replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test')
source = fixture + source + (root/'Sources/Core/Models/TaskVisibility.swift').read_text() + tests
for name in ['HintModels', 'HintScenarios', 'HintCenter']:
    source += '\n' + (root/f'Sources/DesignSystem/Hints/{name}.swift').read_text()
# Use the actual shared XCTest method; routine tests remain outside this run.
hints = (root/'Tests/HintCenterTests.swift').read_text()
marker = '    func testAllTasksHintCompletes()'
if marker in hints:
    start = hints.index(marker); opening = hints.index('{', start); end = opening + 1; depth = 1
    while depth:
        depth += (hints[end] == '{') - (hints[end] == '}'); end += 1
    method = hints[start:end].replace('    func test', '    @objc func test')
    source += '\n@MainActor final class AllTasksHintHostTests: XCTestCase {\n' + method + '\n}\n'
    suites = 'ProjectTaskFilterTests.defaultTestSuite, AllTasksHintHostTests.defaultTestSuite'
else:
    suites = 'ProjectTaskFilterTests.defaultTestSuite'
source += '\nlet suites = [' + suites + ']\nfor suite in suites { suite.run() }\nexit(suites.allSatisfy { $0.testRun!.hasSucceeded } ? 0 : 1)\n'
dev = Path(subprocess.check_output(['xcode-select','-p'], text=True).strip())
f = dev/'Platforms/MacOSX.platform/Developer/Library/Frameworks'
l = dev/'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='project-filters-') as tmp:
    main = Path(tmp)/'main.swift'; main.write_text(source); binary = Path(tmp)/'tests'
    subprocess.run(['swiftc','-F',str(f),'-I',str(l),'-L',str(l),'-Xlinker','-rpath','-Xlinker',str(f),'-Xlinker','-rpath','-Xlinker',str(l),str(main),'-o',str(binary)],check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
