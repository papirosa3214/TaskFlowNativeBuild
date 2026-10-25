#!/usr/bin/env python3
"""Run the real chat live-text pacer and its XCTest cases on macOS, without a simulator.

Only the declarations the pacer needs are lifted out of
Sources/Core/Models/RoleChat.swift, so the production code under test is the
same source the app ships. Nothing from the app module is required.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

SOURCE_PATH = 'Sources/Core/Models/RoleChat.swift'
TESTS_PATH = 'Tests/RoleChatPacerPrefixTests.swift'

DECLARATIONS = [
    'public enum RoleChatLiveItem',
    'public struct RoleChatThinking',
    'enum RoleChatTime',
    'struct RoleLiveTextPacer',
    'public struct RoleChatLiveStep',
]

# Фикстура вместо ChatRichContent: pacer спрашивает у него только списки
# языков, ради которых блок считается «особенным».
FIXTURE = '''
enum ChatRichContent {
    static let htmlLanguages: Set<String> = ["html", "artifact"]
    static let widgetLanguages: Set<String> = ["widget", "tf-widget"]
}
'''


def declaration_source(path: Path, header: str) -> str:
    source = path.read_text()
    start = source.index(header)
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


def main() -> int:
    source_path = ROOT / SOURCE_PATH
    if '--legacy' in sys.argv:
        # Тот же тест против кода из HEAD — до правки: показывает, что
        # проверка ловит именно поломку, а не следствие правки.
        head = subprocess.check_output(['git', '-C', str(ROOT), 'show', f'HEAD:{SOURCE_PATH}'], text=True)
        head_path = Path(tempfile.mkdtemp(prefix='taskflow-chat-pacer-head-')) / 'RoleChat.swift'
        head_path.write_text(head)
        source_path = head_path
        print('HEAD pacer (before the fix): expecting failures')
    tests = (ROOT / TESTS_PATH).read_text().replace('@testable import TaskFlow', '')
    names = re.findall(r'func (test\w+)\(', tests)
    tests = tests.replace('    func test', '    @objc func test')
    runner = (
        '\nlet suite = RoleChatPacerPrefixTests.defaultTestSuite\n'
        'suite.run()\n'
        'let run = suite.testRun!\n'
        f'if run.executionCount != {len(names)} {{ exit(2) }}\n'
        'exit(run.hasSucceeded ? 0 : 1)\n'
    )

    parts = ['import Foundation', FIXTURE]
    parts.append(declaration_source(ROOT / 'Sources/Core/Common/DateFormats.swift', 'public enum DateFormats'))
    parts.append(declaration_source(ROOT / 'Sources/Core/Common/CalendarDateMath.swift', 'public enum CalendarDateMath'))
    for header in DECLARATIONS:
        parts.append(declaration_source(source_path, header))
    source = '\n'.join(parts) + '\n' + tests + runner

    with tempfile.TemporaryDirectory(prefix='taskflow-chat-pacer-') as folder:
        folder = Path(folder)
        main_file = folder / 'main.swift'
        binary = folder / 'tests'
        main_file.write_text(source)
        developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
        frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
        libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
        subprocess.run(
            [
                'swiftc',
                '-F', str(frameworks),
                '-I', str(libraries),
                '-L', str(libraries),
                '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                '-Xlinker', '-rpath', '-Xlinker', str(libraries),
                str(main_file), '-o', str(binary),
            ],
            check=True,
        )
        result = subprocess.run([str(binary)])
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
