#!/usr/bin/env python3
"""Run the production project counter policy on macOS; no simulator.

Fixtures model policy inputs, not the full REST decoder. The effective task
state property and aggregation implementation come from production sources.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


task_source = (ROOT / 'Sources/Core/Models/Task.swift').read_text()
source = '''
import Foundation
import XCTest
enum TaskStatus: String, Decodable { case active, completed }
enum AgentState: String, Decodable { case inProgress = "in_progress", blocked, review, todo }
struct ApiProject: Decodable {
    let id: String
    let taskCount: Int?
    let completedCount: Int?
    enum CodingKeys: String, CodingKey {
        case id, taskCount = "task_count", completedCount = "completed_count"
    }
}
struct ApiTask: Decodable {
    let projectId: String?
    let status: TaskStatus
    let agentState: AgentState?
    let branchAgentState: AgentState?
    let agentStale: Bool?
    let archivedAt: String?
'''
source += block(task_source, 'public var listAgentState:').replace('public ', '') + '\n'
source += block(task_source, 'public var isArchived:').replace('public ', '') + '\n'
source += '''
    enum CodingKeys: String, CodingKey {
        case status, projectId = "project_id", agentState = "agent_state",
             branchAgentState = "branch_agent_state", agentStale = "agent_stale",
             archivedAt = "archived_at"
    }
}
'''
source += (ROOT / 'Sources/Features/Projects/ProjectTaskFilter.swift').read_text()
source += block((ROOT / 'Sources/Features/Projects/ProjectCard.swift').read_text(),
                'struct ProjectTaskStatusSummary {')
source += '\n' + (ROOT / 'Tests/ProjectSummaryTests.swift').read_text().replace('@testable import TaskFlow', '')
source += '\nlet suite = ProjectSummaryTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
dev = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = dev / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
libraries = dev / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='project-summary-') as folder:
    main = Path(folder) / 'main.swift'
    binary = Path(folder) / 'tests'
    main.write_text(source)
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
                    '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                    '-Xlinker', '-rpath', '-Xlinker', str(libraries), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
