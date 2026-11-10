#!/usr/bin/env python3
"""Подпись работы роли: XCTest на macOS, без симулятора.

Владелец 10.11.2026: «как в T3 — работа свёрнута полосой, время тикает, но не
дёргает ленту». Текст подписи — чистая функция `RoleWorkFooter`, см.
`Tests/RoleWorkFooterTests.swift`.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sources = [
    root / 'Sources/Features/Roles/RoleWorkFooter.swift',
    root / 'Sources/Features/Roles/RoleLiveFormat.swift',
]
tests = root / 'Tests/RoleWorkFooterTests.swift'

missing = [str(p) for p in sources if not p.exists()]
if missing:
    print('RED: нет файлов ' + ', '.join(missing))
    sys.exit(1)

with tempfile.TemporaryDirectory(prefix='role-work-footer-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text(
        tests.read_text()
        + '\nlet suite = RoleWorkFooterTests.defaultTestSuite\n'
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
        *[str(s) for s in sources], str(main), '-o', str(binary),
    ], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)
