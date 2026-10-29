#!/usr/bin/env python3
"""Run quick-action override policy on macOS, no Simulator.

Правила правок быстрых действий — чистая логика без SwiftUI, поэтому
проверяются на хосте.
"""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[1]
starter = root / 'Sources/Core/Models/RoleChatStarter.swift'
actions = root / 'Sources/Core/Models/RoleChatQuickAction.swift'
tests = root / 'Tests/RoleChatQuickActionTests.swift'
for f in (starter, actions, tests):
    if not f.exists():
        raise SystemExit(f'нет файла: {f}')

source = starter.read_text() + '\n' + actions.read_text()
source += '\n' + tests.read_text().replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test')
source += '\nlet suite = RoleChatQuickActionTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n'

d = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
f = d / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
l = d / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='tf-quick-actions-') as tmp:
    p = Path(tmp)
    (p / 'main.swift').write_text(source)
    subprocess.run(['swiftc', '-F', str(f), '-I', str(l), '-L', str(l),
                    '-Xlinker', '-rpath', '-Xlinker', str(f),
                    '-Xlinker', '-rpath', '-Xlinker', str(l),
                    str(p / 'main.swift'), '-o', str(p / 'tests')], check=True)
    raise SystemExit(subprocess.run([str(p / 'tests')]).returncode)
