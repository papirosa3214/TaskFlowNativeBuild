#!/usr/bin/env python3
"""Собрать модели вопроса и правила быстрых вариантов на macOS; без симулятора.

Тот же приём, что в Tools/test_chat_scroll_trace.py: swiftc + XCTest.
Модели из Sources/Core/Models не тянут SwiftUI, поэтому собираются отдельно
от приложения.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sources = [
    root / 'Sources/Core/Models/ChatQuestion.swift',
    root / 'Sources/Core/Models/ChatQuickReplyPolicy.swift',
]
test_files = [
    root / 'Tests/RoleQuestionTests.swift',
    root / 'Tests/ChatQuickReplyPolicyTests.swift',
]
for path in sources + test_files:
    if not path.exists():
        raise SystemExit(f'RED: {path.relative_to(root)} отсутствует — правка не реализована')

fixture = '''import Foundation
/// Заглушки символов приложения: тесты трогают только модели.
struct RoleChatMessage: Decodable {
    let id: String
    let text: String
    let isSessionMarker: Bool
    let question: ChatQuestion?
    enum CodingKeys: String, CodingKey {
        case id, text
        case isSessionMarker = "is_session_marker"
        case question
    }
}
'''

with tempfile.TemporaryDirectory(prefix='chat-question-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    body = fixture
    for test_file in test_files:
        text = test_file.read_text().replace('import XCTest\n@testable import TaskFlow\n', 'import XCTest\n')
        body += '\n' + text
    body += '\nlet a = RoleQuestionTests.defaultTestSuite\nlet b = ChatQuickReplyPolicyTests.defaultTestSuite\na.run()\nb.run()\nexit((a.testRun!.hasSucceeded && b.testRun!.hasSucceeded) ? 0 : 1)\n'
    main.write_text(body)
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
                    '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath',
                    '-Xlinker', str(libraries),
                    *[str(path) for path in sources], str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
