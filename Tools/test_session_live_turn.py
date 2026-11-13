#!/usr/bin/env python3
"""Живой ход и история сессии в модели хода роли — XCTest на macOS, без симулятора.

Собирает настоящий `Sources/Features/Sessions/SessionLiveTurn.swift`, настоящий
`JSONValue` движка сессий и тесты `Tests/SessionLiveTurnTests.swift`. Модели
хода роли (`RoleChatLiveItem` и соседи) живут в большом файле с декодерами и
реестрами — для теста подкладываются их копии с теми же полями и init.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Features/Sessions/SessionLiveTurn.swift'
json_value = root / 'Packages/NewChatCore/Sources/NewChatCore/JSONValue.swift'
tests = root / 'Tests/SessionLiveTurnTests.swift'

if not source.exists():
    print('RED: SessionLiveTurn.swift отсутствует')
    sys.exit(1)

STUB = '''
import Foundation

public enum RoleChatLiveItem: Equatable {
    case text(String)
    case step(RoleChatLiveStep)
    case thinking(RoleChatThinking)
}

public struct RoleChatThinking: Equatable {
    public let id: String
    public let text: String
    public let isRunning: Bool
    public let startedAt: String?
    public let endedAt: String?
    public init(id: String, text: String, isRunning: Bool, startedAt: String? = nil, endedAt: String? = nil) {
        self.id = id; self.text = text; self.isRunning = isRunning
        self.startedAt = startedAt; self.endedAt = endedAt
    }
}

public struct RoleChatLiveStep: Equatable {
    public enum Status: String { case running, done, error }
    public let id: String
    public let tool: String
    public let detail: String?
    public let status: Status
    public let startedAt: String?
    public let endedAt: String?
    public let resultReceived: Bool
    public var args: String? = nil
    public var output: String? = nil
    public var hasArgs = false
    public var hasOutput = false
    public init(id: String, tool: String, detail: String?, status: Status,
                startedAt: String? = nil, endedAt: String? = nil, resultReceived: Bool? = nil) {
        self.id = id; self.tool = tool; self.detail = detail; self.status = status
        self.startedAt = startedAt; self.endedAt = endedAt
        self.resultReceived = resultReceived ?? (status != .running)
    }
}
'''

with tempfile.TemporaryDirectory(prefix='session-live-turn-') as tmp:
    tmp = Path(tmp)
    (tmp / 'stub.swift').write_text(STUB)
    (tmp / 'json.swift').write_text(json_value.read_text())
    (tmp / 'turn.swift').write_text(source.read_text())
    (tmp / 'main.swift').write_text(
        tests.read_text()
        + '\nlet suite = SessionLiveTurnTests.defaultTestSuite\n'
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
        str(tmp / 'stub.swift'), str(tmp / 'json.swift'), str(tmp / 'turn.swift'), str(tmp / 'main.swift'),
        '-o', str(binary),
    ], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)
