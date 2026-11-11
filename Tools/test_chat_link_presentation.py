#!/usr/bin/env python3
"""Ссылки в ответе роли: иконка хоста и короткая подпись — XCTest на macOS.

Владелец 10.11.2026: «вид нужен и визуал отображения всяких ссылок».
Правила живут в чистой `ChatLinkPresentation` — см.
`Tests/ChatLinkPresentationTests.swift`.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Chat/Feed/ChatLinkPresentation.swift'
destination = root / 'Sources/Chat/Panels/ChatMaterialDestination.swift'
tests = root / 'Tests/ChatLinkPresentationTests.swift'

if not source.exists():
    # RED: файла ещё нет — тест обязан упасть.
    print('RED: ChatLinkPresentation.swift отсутствует')
    sys.exit(1)

with tempfile.TemporaryDirectory(prefix='chat-link-presentation-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text(
        tests.read_text()
        + '\nlet suite = ChatLinkPresentationTests.defaultTestSuite\n'
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
        str(source), str(destination), str(main), '-o', str(binary),
    ], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)
