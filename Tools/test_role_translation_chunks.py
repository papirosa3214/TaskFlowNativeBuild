#!/usr/bin/env python3
"""Куски перевода: нарезка текста и сборка показа — XCTest на macOS, без симулятора.

Перевод реплик роли (владелец 08.11.2026) — см.
`Tests/RoleTranslationChunksTests.swift` и
`Sources/Features/Roles/RoleTranslationChunks.swift`.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Features/Roles/RoleTranslationChunks.swift'
tests = root / 'Tests/RoleTranslationChunksTests.swift'

if not source.exists():
    # RED: файла ещё нет — тест обязан упасть.
    print('RED: RoleTranslationChunks.swift отсутствует')
    sys.exit(1)

with tempfile.TemporaryDirectory(prefix='role-translation-chunks-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text(
        tests.read_text()
        + '\nlet suite = RoleTranslationChunksTests.defaultTestSuite\n'
        + 'suite.run()\n'
        + 'exit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
    )
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run([
        'swiftc',
        '-F', str(frameworks),
        '-I', str(libraries),
        '-L', str(libraries),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        '-Xlinker', '-rpath', '-Xlinker', str(libraries),
        str(source), str(main), '-o', str(binary),
    ], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)
