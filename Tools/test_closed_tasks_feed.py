#!/usr/bin/env python3
"""Архив и статистика закрытых задач на телефоне — XCTest на macOS, без симулятора.

Собирает настоящий `Sources/Core/Models/ClosedTasksFeed.swift` (чистая логика,
только Foundation) и тесты `Tests/ClosedTasksFeedTests.swift`.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Core/Models/ClosedTasksFeed.swift'
tests = root / 'Tests/ClosedTasksFeedTests.swift'

if not source.exists():
    print('RED: ClosedTasksFeed.swift отсутствует')
    sys.exit(1)

with tempfile.TemporaryDirectory(prefix='closed-tasks-feed-') as tmp:
    tmp = Path(tmp)
    (tmp / 'feed.swift').write_text(source.read_text())
    (tmp / 'main.swift').write_text(
        tests.read_text()
        + '\nlet suite = ClosedTasksFeedTests.defaultTestSuite\n'
        + 'suite.run()\n'
        + 'exit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
    )
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    binary = tmp / 'tests'
    subprocess.run([
        'swiftc',
        '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        '-Xlinker', '-rpath', '-Xlinker', str(libraries),
        str(tmp / 'feed.swift'), str(tmp / 'main.swift'),
        '-o', str(binary),
    ], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)
