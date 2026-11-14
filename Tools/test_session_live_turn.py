#!/usr/bin/env python3
"""Живой ход и история сессии — XCTest на macOS, без симулятора.

Собирает настоящие файлы, без копий: `Sources/Features/Sessions/SessionLiveTurn.swift`,
модели хода роли (`Sources/Core/Models`), общие типы (`Sources/Core/Common`),
разбор ответа (`Sources/Chat/Feed/ChatRichContent.swift`) и тесты
`Tests/SessionLiveTurnTests.swift`.

AgentTrace требует сетевой `TaskLiveTurn`, SafePasteboard — UIKit: они
исключены, модели хода их не используют.

`--against=SHA` — те же тесты против исходников из явного коммита (нужно, чтобы
отличить падение из-за правки от падения, которое было и до неё).
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Features/Sessions/SessionLiveTurn.swift'
tests = root / 'Tests/SessionLiveTurnTests.swift'
SKIP = {'Sources/Core/Models/AgentTrace.swift', 'Sources/Core/Common/SafePasteboard.swift'}

against = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--against=')), None)


def source_text(path: str) -> str:
    """Исходник из указанного коммита или из рабочего дерева."""
    if against:
        shown = subprocess.run(['git', '-C', str(root), 'show', f'{against}:{path}'],
                               capture_output=True, text=True)
        if shown.returncode == 0:
            return shown.stdout
        print(f'RED: {path} нет в {against}')
        sys.exit(1)
    return (root / path).read_text()


if not source.exists():
    print('RED: SessionLiveTurn.swift отсутствует')
    sys.exit(1)

FILES = (
    sorted(f'Sources/Core/Models/{p.name}' for p in (root / 'Sources/Core/Models').glob('*.swift'))
    + sorted(f'Sources/Core/Common/{p.name}' for p in (root / 'Sources/Core/Common').glob('*.swift'))
    + ['Sources/Chat/Feed/ChatRichContent.swift']
)
FILES = [f for f in FILES if f not in SKIP] + [str(source.relative_to(root))]

with tempfile.TemporaryDirectory(prefix='session-live-turn-') as tmp:
    tmp = Path(tmp)
    for index, path in enumerate(FILES):
        (tmp / f'source{index:03d}.swift').write_text(source_text(path))
    (tmp / 'main.swift').write_text(
        source_text(str(tests.relative_to(root)))
        + '\nlet suite = SessionLiveTurnTests.defaultTestSuite\n'
        + 'suite.run()\n'
        + 'exit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
    )
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    binary = tmp / 'tests'
    build = subprocess.run([
        'swiftc',
        '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        '-Xlinker', '-rpath', '-Xlinker', str(libraries),
        *sorted(str(path) for path in tmp.glob('*.swift')),
        '-o', str(binary),
    ], capture_output=True, text=True)
    if build.returncode != 0:
        print(build.stderr[-6000:])
        sys.exit(build.returncode)
    sys.exit(subprocess.run([str(binary)]).returncode)
