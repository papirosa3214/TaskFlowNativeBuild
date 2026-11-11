#!/usr/bin/env python3
"""Раскрытие блока действий хода переживает пересборку строки ленты.

Владелец 11.11.2026: раскрыл блок действий роли, начал прокручивать — блок
схлопнулся сам. Раскрытие жило в `@State` строки, а лента на `UITableView`
строку пересобирает при обновлении данных и при переиспользовании ячейки.
Теперь оно в `RoleFeedExpansion` — см. `Tests/RoleFeedExpansionTests.swift`.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Features/Roles/RoleFeedExpansion.swift'
tests = root / 'Tests/RoleFeedExpansionTests.swift'

if not source.exists():
    # RED: файла ещё нет или раскрытие всё ещё в @State строки.
    print('RED: RoleFeedExpansion.swift отсутствует — раскрытие по-прежнему в @State строки')
    sys.exit(1)

# Раскрытие не должно вернуться в @State строки: строка ленты пересобирается
# при обновлении данных и при переиспользовании ячейки, и @State начинается
# заново — это и есть самопроизвольное сворачивание.
group = root / 'Sources/Features/Roles/RoleActionGroup.swift'
group_text = group.read_text()
if '@State private var expanded' in group_text:
    print('RED: RoleActionGroup держит раскрытие в @State строки')
    sys.exit(1)
if 'onToggle' not in group_text:
    print('RED: RoleActionGroup не сообщает о переключении наружу — раскрытие снова локальное')
    sys.exit(1)
turn_view = root / 'Sources/Features/Roles/RoleLiveTurnView.swift'
if 'expansion: RoleFeedExpansion' not in turn_view.read_text():
    print('RED: RoleLiveTurnView не берёт раскрытие из RoleFeedExpansion')
    sys.exit(1)

with tempfile.TemporaryDirectory(prefix='role-feed-expansion-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text(
        tests.read_text()
        + '\nlet suite = RoleFeedExpansionTests.defaultTestSuite\n'
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
        str(source), str(main), '-o', str(binary),
    ], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)
