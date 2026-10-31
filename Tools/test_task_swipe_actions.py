#!/usr/bin/env python3
"""Run the actual swipe-policy enums and their XCTest cases on macOS, without an iOS app.

The tiny ApiTask fixture exposes only the stored values read by the policies.
This checks selection behavior, not the production model decoder or UI.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def enum_source(path, name):
    source = (ROOT / path).read_text()
    start = source.index(f'enum {name}:')
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]

fixture = r'''
import Foundation
import XCTest

enum TaskStatus: String, Decodable { case active, completed }
enum AgentState: String, Decodable { case inProgress = "in_progress", blocked, review, todo }
struct ApiTask: Decodable {
    var status: TaskStatus
    var assigneeId: String?
    var agentState: AgentState?
    var readyForPickup: Bool
    init(status: TaskStatus = .active, assigneeId: String? = nil, agentState: AgentState? = nil, readyForPickup: Bool = false) {
        self.status = status; self.assigneeId = assigneeId
        self.agentState = agentState; self.readyForPickup = readyForPickup
    }
    enum CodingKeys: String, CodingKey { case status, assigneeId = "assignee_id", agentState = "agent_state", readyForPickup = "ready_for_pickup" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(TaskStatus.self, forKey: .status)
        assigneeId = try c.decodeIfPresent(String.self, forKey: .assigneeId)
        agentState = try c.decodeIfPresent(AgentState.self, forKey: .agentState)
        readyForPickup = try c.decodeIfPresent(Int.self, forKey: .readyForPickup) == 1
    }
}
enum TestTaskFactory {
    static func makeTask(id: String, assigneeId: String? = nil, agentState: AgentState? = nil) -> ApiTask {
        ApiTask(assigneeId: assigneeId, agentState: agentState)
    }
}
'''
tests = (ROOT / 'Tests/TodayTaskSwipeActionTests.swift').read_text().replace('@testable import TaskFlow', '')
names = re.findall(r'func (test\w+)\(', tests)
tests = tests.replace('    func test', '    @objc func test')
runner = f'\nlet suite = TodayTaskSwipeActionTests.defaultTestSuite\nsuite.run()\nlet run = suite.testRun!\nif run.executionCount != {len(names)} {{ exit(2) }}\nexit(run.hasSucceeded ? 0 : 1)\n'

source = fixture + enum_source('Sources/Features/Today/TodayTaskRow.swift', 'TodayTaskSwipeAction') + '\n' + enum_source('Sources/Features/Shared/DirectoryTaskRow.swift', 'ProjectTaskSwipeAction') + '\n' + tests + runner
with tempfile.TemporaryDirectory(prefix='taskflow-swipe-host-') as folder:
    folder = Path(folder)
    main = folder / 'main.swift'
    binary = folder / 'tests'
    main.write_text(source)
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), str(main), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)])
    raise SystemExit(result.returncode)
