#!/usr/bin/env python3
"""Run the real chat tail-follow policy and its XCTest cases on macOS, without a simulator.

The policy is pure logic (Sources/Core/Models/ChatFeedTailFollow.swift), so the
production source is compiled as it is in the repository.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

SOURCE_PATH = 'Sources/Core/Models/ChatFeedTailFollow.swift'
TESTS_PATH = 'Tests/RoleChatTailFollowTests.swift'


LEGACY = r'''
import Foundation

/// Зеркало прежнего поведения: содержимое пересобралось — лента остаётся
/// на прежнем смещении, ничего не возвращается к хвосту.
struct ChatFeedTailFollow: Equatable {
    private(set) var wasAtTail: Bool = true
    static let atTailTolerance: Double = 200
    static let heightChangeThreshold: Double = 4
    init() {}
    mutating func update(distanceToBottom: Double) { }
    static func needsCompensation(heightDelta: Double, wasAtTail: Bool) -> Bool { false }
}
'''


def main() -> int:
    policy = LEGACY if '--legacy' in sys.argv else (ROOT / SOURCE_PATH).read_text()
    tests = (ROOT / TESTS_PATH).read_text().replace('@testable import TaskFlow', '')
    names = re.findall(r'func (test\w+)\(', tests)
    tests = tests.replace('    func test', '    @objc func test')
    runner = (
        '\nlet suite = RoleChatTailFollowTests.defaultTestSuite\n'
        'suite.run()\n'
        'let run = suite.testRun!\n'
        f'if run.executionCount != {len(names)} {{ exit(2) }}\n'
        'exit(run.hasSucceeded ? 0 : 1)\n'
    )

    source = policy + '\n' + tests + runner
    with tempfile.TemporaryDirectory(prefix='taskflow-chat-tail-follow-') as folder:
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
        return subprocess.run([str(binary)]).returncode


if __name__ == '__main__':
    raise SystemExit(main())
