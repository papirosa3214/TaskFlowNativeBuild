#!/usr/bin/env python3
"""Run production TaskVisibility policy on macOS; no simulator.

The ApiTask fixture models only the inputs the policy reads (status,
archived_at) - not the full REST decoder. RED before the policy existed:
the file was missing, so the compile failed with "cannot find 'TaskVisibility'
in scope"; GREEN after: the policy passes the same assertions.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
policy = root / 'Sources/Core/Models/TaskVisibility.swift'

fixture = '''
import Foundation
import XCTest
enum TaskStatus: String, Decodable { case active, completed }
struct ApiTask: Decodable {
    let id: String
    let title: String
    let status: TaskStatus
    let archivedAt: String?
    var isArchived: Bool { archivedAt != nil }
    enum CodingKeys: String, CodingKey {
        case id, title, status
        case archivedAt = "archived_at"
    }
}
'''

if not policy.exists():
    print('FAIL: нет Sources/Core/Models/TaskVisibility.swift — правил видимости нет')
    raise SystemExit(1)

source = policy.read_text()
tests = (root / 'Tests/TaskVisibilityTests.swift').read_text() \
    .replace('@testable import TaskFlow', '') \
    .replace('    func test', '    @objc func test')
program = fixture + source + '\n' + tests + '''
let suite = TaskVisibilityTests.defaultTestSuite
suite.run()
exit(suite.testRun!.hasSucceeded ? 0 : 1)
'''

dev = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = dev / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
libraries = dev / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='task-visibility-') as tmp:
    main = Path(tmp) / 'main.swift'
    main.write_text(program)
    binary = Path(tmp) / 'tests'
    subprocess.run([
        'swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        '-Xlinker', '-rpath', '-Xlinker', str(libraries),
        str(main), '-o', str(binary),
    ], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
