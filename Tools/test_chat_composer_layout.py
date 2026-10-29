#!/usr/bin/env python3
"""Run chat composer layout policy on macOS, no Simulator.

Правила раскладки и каретки — чистая логика без SwiftUI, поэтому проверяются
на хосте.
"""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[1]
style = root / 'Sources/Core/Models/ChatComposerStyle.swift'
layout = root / 'Sources/Core/Models/ChatComposerLayout.swift'
tests = root / 'Tests/ChatComposerLayoutTests.swift'
for f in (style, layout, tests):
    if not f.exists():
        raise SystemExit(f'нет файла: {f}')

source = style.read_text() + '\n' + layout.read_text()
source += '\n' + tests.read_text().replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test')
source += '\nlet suite = ChatComposerLayoutTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n'

d = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
f = d / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
l = d / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='tf-composer-layout-') as tmp:
    p = Path(tmp)
    (p / 'main.swift').write_text(source)
    subprocess.run(['swiftc', '-F', str(f), '-I', str(l), '-L', str(l),
                    '-Xlinker', '-rpath', '-Xlinker', str(f),
                    '-Xlinker', '-rpath', '-Xlinker', str(l),
                    str(p / 'main.swift'), '-o', str(p / 'tests')], check=True)
    raise SystemExit(subprocess.run([str(p / 'tests')]).returncode)
