#!/usr/bin/env python3
"""Compile the live-delta reducer, the task router and XCTest on macOS; no simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
sources = [root / 'Sources/Core/Realtime/RoleChatLiveDelta.swift', root / 'Sources/Core/Realtime/TaskLiveDeltaRouter.swift']
for source in sources:
    if not source.exists():
        raise SystemExit(f'RED: {source.name} is absent')
with tempfile.TemporaryDirectory(prefix='task-live-delta-router-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text((root / 'Tests/TaskLiveDeltaRouterTests.swift').read_text() + '\nlet suite = TaskLiveDeltaRouterTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n')
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), *map(str, sources), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
