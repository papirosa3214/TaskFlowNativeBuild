#!/usr/bin/env python3
"""Run the real chat tail policy and its XCTest cases on macOS, without a simulator.

Default mode compiles Sources/Core/Models/ChatTailPolicy.swift as it is in the
repository. --legacy mode compiles a stand-in that mirrors the behaviour the
chat window had before the fix (the sticky ScrollPosition.isPositionedByUser
flag), so the same expectations can be shown failing before the change.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

POLICY_PATH = 'Sources/Core/Models/ChatTailPolicy.swift'
TESTS_PATH = 'Tests/RoleChatTailPolicyTests.swift'

LEGACY_POLICY = r'''
import Foundation

/// Зеркало прежнего поведения окна чата: одноразовый флаг
/// ScrollPosition.isPositionedByUser. Как только пользователь прокрутил
/// ленту, слежение за хвостом выключалось навсегда, и назад не включалось.
struct ChatTailPolicy: Equatable {
    enum Event: Equatable {
        case entered
        case userScrolled(nearBottom: Bool)
        case jumpedToTail
        case jumpedToMessage
    }

    private(set) var isPositionedByUser: Bool = false
    private(set) var userDrivesScroll: Bool = false

    var followsTail: Bool { !isPositionedByUser }

    init() {}

    mutating func handle(_ event: Event) {
        switch event {
        case .entered, .jumpedToTail, .jumpedToMessage:
            break
        case .userScrolled:
            isPositionedByUser = true
        }
    }

    mutating func userStartedDriving() {
        userDrivesScroll = true
    }

    mutating func userStoppedDriving(nearBottom: Bool) {
        userDrivesScroll = false
        isPositionedByUser = true
    }
}
'''


def run(policy_source: str, expect_success: bool) -> int:
    tests = (ROOT / TESTS_PATH).read_text().replace('@testable import TaskFlow', '')
    names = [n for n in __import__('re').findall(r'func (test\w+)\(', tests)]
    tests = tests.replace('    func test', '    @objc func test')
    runner = (
        '\nlet suite = RoleChatTailPolicyTests.defaultTestSuite\n'
        'suite.run()\n'
        'let run = suite.testRun!\n'
        f'if run.executionCount != {len(names)} {{ exit(2) }}\n'
        'exit(run.hasSucceeded ? 0 : 1)\n'
    )

    source = policy_source + '\n' + tests + runner
    with tempfile.TemporaryDirectory(prefix='taskflow-chat-tail-') as folder:
        folder = Path(folder)
        main = folder / 'main.swift'
        binary = folder / 'tests'
        main.write_text(source)
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
                str(main), '-o', str(binary),
            ],
            check=True,
        )
        result = subprocess.run([str(binary)])
        ok = result.returncode == 0
        if ok != expect_success:
            mode = 'legacy' if expect_success is False else 'production'
            print(f'{mode}: unexpected result (exit {result.returncode})')
            return 2
        return 0


def main() -> int:
    legacy = '--legacy' in sys.argv
    policy = LEGACY_POLICY if legacy else (ROOT / POLICY_PATH).read_text()
    if legacy:
        print('legacy behaviour (sticky isPositionedByUser): expecting failures')
    else:
        print('production policy: expecting green')
    return run(policy, expect_success=not legacy)


if __name__ == '__main__':
    raise SystemExit(main())
