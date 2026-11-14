#!/usr/bin/env python3
"""Область живой разметки хода сессии — XCTest на macOS, без симулятора.

Собирает настоящие `ChatServerBlock.swift` (общий `ChatLiveBlockRegistry`),
`ChatRichContent.swift` (путь экрана живого ответа), модели заметок, движок
значений и тесты `Tests/ChatLiveBlockScopeTests.swift`; из `SessionLiveTurnView`
берётся настоящий блок `SessionLiveReplyContent` — то, что экран сессии
передаёт в разметку.

Зачем область: реестр искал блоки по тексту реплики, поэтому два параллельных
хода с одинаковым или пересекающимся текстом доставали чужие блоки.

`--against=old` собирает те же тесты против реестра и экранного пути из HEAD
(до правки) плюс тонкий шим, который принимает область, но, как старый код,
ищет только по тексту. Это и есть RED: тест падает на старом поведении.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
old = '--against=old' in sys.argv

FILES = {
    'json': 'Sources/Core/Common/JSONValue.swift',
    'cache': 'Sources/Core/Common/ParsedValueCache.swift',
    'component': 'Sources/Core/Models/AgentComponent.swift',
    'registry': 'Sources/Core/Models/ChatServerBlock.swift',
    'notes': 'Sources/Core/Models/NoteDocument.swift',
    'rich': 'Sources/Chat/Feed/ChatRichContent.swift',
}
tests = root / 'Tests/ChatLiveBlockScopeTests.swift'
screen = root / 'Sources/Features/Sessions/SessionLiveTurnView.swift'


def current(path: str) -> str:
    return (root / path).read_text()


def from_head(path: str) -> str:
    return subprocess.check_output(['git', '-C', str(root), 'show', f'HEAD:{path}'], text=True)


def screen_block(text: str) -> str:
    """Настоящий `enum SessionLiveReplyContent` из экрана сессии."""
    match = re.search(r'enum SessionLiveReplyContent \{.*?\n\}', text, re.S)
    if not match:
        print('RED: в SessionLiveTurnView нет SessionLiveReplyContent')
        sys.exit(1)
    return match.group(0)


# Старый код знал только текст: шим принимает область и игнорирует её —
# ровно то поведение, ради которого заведена правка.
REGISTRY_SHIM = '''
extension ChatLiveBlockRegistry {
    func register(_ blocks: [ChatLiveBlock], for text: String, scope: String?) {
        register(blocks, for: text)
    }
    func blocks(for text: String, scope: String?) -> [ChatLiveBlock]? {
        blocks(for: text)
    }
    func block(startingWith shown: String, scope: String?) -> ChatLiveBlock? {
        block(startingWith: shown)
    }
}

enum ChatLiveBlockScope {
    static func session(_ sessionID: String, turnStartedAt: Date?) -> String {
        sessionID + ":" + (turnStartedAt?.ISO8601Format() ?? "live")
    }
}
'''

RICH_SHIM = '''
extension ChatRichContent {
    static func liveSegments(shown: String, scope: String?) -> [ChatRichSegment]? {
        liveSegments(shown: shown)
    }
}
'''

REPLY_SHIM = '''
enum SessionLiveReplyContent {
    static func prepared(shown: String, scope: String? = nil) -> [ChatRichSegment]? {
        ChatRichContent.liveSegments(shown: shown, scope: scope)
    }
}
'''

if old:
    sources = {key: current(path) for key, path in FILES.items() if key not in ('registry', 'rich')}
    sources['registry'] = from_head(FILES['registry']) + REGISTRY_SHIM
    sources['rich'] = from_head(FILES['rich']) + RICH_SHIM
    sources['reply'] = REPLY_SHIM
    label = 'RED — реестр и экран из HEAD (поиск только по тексту)'
else:
    sources = {key: current(path) for key, path in FILES.items()}
    sources['reply'] = screen_block(current('Sources/Features/Sessions/SessionLiveTurnView.swift'))
    label = 'GREEN — область живой разметки (сессия + ход)'

with tempfile.TemporaryDirectory(prefix='chat-live-scope-') as tmp:
    tmp = Path(tmp)
    for key, text in sources.items():
        (tmp / f'{key}.swift').write_text(text)
    (tmp / 'main.swift').write_text(
        tests.read_text()
        + '\nlet suite = ChatLiveBlockScopeTests.defaultTestSuite\n'
        + 'suite.run()\n'
        + 'exit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
    )
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    binary = tmp / 'tests'
    print(f'== {label}')
    build = subprocess.run([
        'swiftc',
        '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        '-Xlinker', '-rpath', '-Xlinker', str(libraries),
        *sorted(str(path) for path in tmp.glob('*.swift')),
        '-o', str(binary),
    ], capture_output=True, text=True)
    if build.returncode != 0:
        print(build.stderr[-4000:])
        sys.exit(build.returncode)
    sys.exit(subprocess.run([str(binary)]).returncode)
