#!/usr/bin/env python3
"""Compile the chat:work_plan event reducer and XCTest on macOS; no simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
sources = [root / p for p in ('Sources/Core/Models/ChatWorkPlan.swift', 'Sources/Core/Models/SubtaskWorkPlan.swift', 'Sources/Core/Common/JSONValue.swift')]
with tempfile.TemporaryDirectory(prefix='chat-work-plan-event-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    test = (root / 'Tests/ChatWorkPlanEventTests.swift').read_text().replace('@testable import TaskFlow\n', '')
    main.write_text(test + '\nlet suite = ChatWorkPlanEventTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n')
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    built = subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), *map(str, sources), str(main), '-o', str(binary)], capture_output=True, text=True)
    if built.returncode:
        print('\n'.join([l for l in built.stderr.splitlines() if 'error:' in l][:20]))
        raise SystemExit('RED: compile failed')
    raise SystemExit(subprocess.run([str(binary)]).returncode)
