#!/usr/bin/env python3
"""Иконка внутри строки текста — XCTest на macOS, без симулятора."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Chat/Feed/ChatInlineIcon.swift'
tests = root / 'Tests/ChatInlineIconTests.swift'

if not source.exists():
    print('RED: ChatInlineIcon.swift отсутствует')
    sys.exit(1)

# Для теста нужна только геометрия: файл собирается без UIKit-рендера,
# поэтому подкладываем заглушки типов, которые он использует.
with tempfile.TemporaryDirectory(prefix='chat-inline-icon-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    stub = Path(tmp) / 'stub.swift'
    stub.write_text(
        'enum ChatLinkPresentation {\n'
        '    enum Icon { case asset(String), symbol(String) }\n'
        '}\n'
    )
    geometry = Path(tmp) / 'geometry.swift'
    text = source.read_text()
    start = text.index('enum ChatInlineIcon {')
    end = text.index('    /// Готовая картинка под кегль и цвет текста.')
    geometry.write_text('import Foundation\nimport CoreGraphics\n\n' + text[start:end] + '}\n')
    main.write_text(
        tests.read_text()
        + '\nlet suite = ChatInlineIconTests.defaultTestSuite\n'
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
        str(stub), str(geometry), str(main), '-o', str(binary),
    ], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)
