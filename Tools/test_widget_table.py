#!/usr/bin/env python3
"""Compile the widget table parser and its XCTest on macOS; no simulator.

По образцу Tools/test_agent_component.py: модель разбора таблицы виджета
лежит в одном файле без SwiftUI, поэтому её можно собрать и прогнать
на маке обычным swiftc — без симулятора и без сборки приложения.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Features/Chat/Widgets/WidgetTable.swift'
tests = root / 'Tests/WidgetTableTests.swift'
if not source.exists():
    raise SystemExit('RED: WidgetTable.swift is absent')
if not tests.exists():
    raise SystemExit('RED: WidgetTableTests.swift is absent')

with tempfile.TemporaryDirectory(prefix='widget-table-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text(
        tests.read_text()
        + '\nlet suite = WidgetTableTests.defaultTestSuite\n'
        + 'suite.run()\n'
        + 'exit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
    )
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run([
        'swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        '-Xlinker', '-rpath', '-Xlinker', str(libraries),
        str(source), str(main), '-o', str(binary),
    ], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
