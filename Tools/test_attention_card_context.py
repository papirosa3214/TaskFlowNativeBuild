#!/usr/bin/env python3
"""Run the attention card contract on macOS, no Simulator.

Контракт карточки «Входящих» — разбор ответа сервера и правило «что рисуем
под названием». Обе части — чистая логика, их можно проверить на хосте.
"""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[1]
model = root / 'Sources/Core/Models/AttentionFeed.swift'
tests = root / 'Tests/AttentionCardContextTests.swift'
if not model.exists():
    raise SystemExit(f'нет модели: {model}')

source = model.read_text()
source += '\n' + tests.read_text().replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test')
source += '\nlet suite = AttentionCardContextTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n'

d = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
f = d / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
l = d / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='tf-attention-card-') as tmp:
    p = Path(tmp)
    (p / 'main.swift').write_text(source)
    subprocess.run(['swiftc', '-F', str(f), '-I', str(l), '-L', str(l),
                    '-Xlinker', '-rpath', '-Xlinker', str(f),
                    '-Xlinker', '-rpath', '-Xlinker', str(l),
                    str(p / 'main.swift'), '-o', str(p / 'tests')], check=True)
    raise SystemExit(subprocess.run([str(p / 'tests')]).returncode)
