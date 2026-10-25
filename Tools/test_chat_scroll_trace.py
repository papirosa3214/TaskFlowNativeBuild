#!/usr/bin/env python3
"""Compile the actual bounded trace buffer and XCTest on macOS; no simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Core/ChatScrollTrace.swift'
if not source.exists():
    raise SystemExit('RED: ChatScrollTrace.swift is absent; diagnostic recorder not implemented')
with tempfile.TemporaryDirectory(prefix='chat-scroll-trace-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text((root / 'Tests/ChatScrollTraceTests.swift').read_text() + '\nlet suite = ChatScrollTraceTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n')
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), str(source), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
