#!/usr/bin/env python3
"""Разрез списка чатов: внешний агент или внутренняя роль. XCTest на macOS, без симулятора."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/DesignSystem/Components/RoleAvatarAsset.swift'
tests = root / 'Tests/ChatHomeRoleSplitTests.swift'

if not source.exists() or 'isExternalChatRole' not in source.read_text():
    print('RED: RoleAvatarAsset.isExternalChatRole ещё нет')
    sys.exit(1)

with tempfile.TemporaryDirectory(prefix='chat-home-role-split-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text(
        tests.read_text()
        + '\nlet suite = ChatHomeRoleSplitTests.defaultTestSuite\n'
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
