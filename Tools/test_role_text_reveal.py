#!/usr/bin/env python3
"""Проявление готового сообщения: у каждого независимого текста своя история.

Прогон на маке (swiftc + XCTest), без симулятора iOS. Проверяется логика
проявления, а не отрисовка SwiftUI.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Sources/Features/Roles/RoleLiveTurnView.swift'


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


source = SOURCE.read_text()
stubs = '''
import Foundation
enum RoleLiveTextPacer { static let minRate = 60.0; static let maxRate = 900.0 }
'''
# Объявление, которого в исходнике нет, пропускаем: тесты тогда не соберутся
# и прогон упадёт — но не тихо.
production = '\n'.join(
    declaration(source, marker) for marker in (
        'struct RoleTextFade:', 'final class RoleTextRevealTimeline {',
        'final class RoleTextRevealHistory {')
    if marker in source)
tests = (ROOT / 'Tests/RoleTextRevealForwardTests.swift').read_text().replace(
    '@testable import TaskFlow', '')
tests += '\n' + (ROOT / 'Tests/RoleTextRevealHistoryTests.swift').read_text().replace(
    '@testable import TaskFlow', '')
with tempfile.TemporaryDirectory(prefix='role-text-reveal-') as tmp:
    main = Path(tmp) / 'main.swift'
    main.write_text(stubs + production + '\n' + tests + '''
let forward = RoleTextRevealForwardTests.defaultTestSuite
forward.run()
let history = RoleTextRevealHistoryTests.defaultTestSuite
history.run()
exit(forward.testRun!.hasSucceeded && history.testRun!.hasSucceeded ? 0 : 1)
''')
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    binary = Path(tmp) / 'tests'
    subprocess.run(['swiftc', '-F', str(frameworks),
                    '-I', str(libraries), '-L', str(libraries),
                    '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                    '-Xlinker', '-rpath', '-Xlinker', str(libraries),
                    str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
