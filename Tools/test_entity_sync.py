#!/usr/bin/env python3
"""Проверка правил догона сущностей вне карточек на macOS — без симулятора.

Гоняет настоящие правила (`Sources/Core/Store/EntitySyncPolicy.swift`) и
настоящие тесты (`Tests/EntitySyncPolicyTests.swift`) на macOS: файл правил
не тянет ни БД, ни сети, поэтому собирается swiftc без симулятора.

Дополнительно — СТАТИЧЕСКАЯ проверка, что догон подключён в приложении и что
курсор двигается только после применения данных (правило «курсор не раньше
применения»).

Запуск: python3 Tools/test_entity_sync.py
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
policy_path = root/'Sources/Core/Store/EntitySyncPolicy.swift'
tests_path = root/'Tests/EntitySyncPolicyTests.swift'
catchup_path = root/'Sources/Core/Store/EntitySyncCatchUp.swift'
api_path = root/'Sources/Core/Networking/APIClient+EntitySync.swift'
app_path = root/'Sources/App/TaskFlowApp.swift'

for path in (policy_path, tests_path, catchup_path, api_path, app_path):
    if not path.exists():
        raise SystemExit(f'нет файла: {path}')

policy = policy_path.read_text()
tests = (tests_path.read_text()
         .replace('@testable import TaskFlow', '')
         .replace('    func test', '    @objc func test'))

source = policy + '\n' + tests + '\n'
source += '''
let suites = [EntitySyncPolicyTests.defaultTestSuite]
for suite in suites { suite.run() }
exit(suites.allSatisfy { $0.testRun!.hasSucceeded } ? 0 : 1)
'''

dev = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = dev/'Platforms/MacOSX.platform/Developer/Library/Frameworks'
lib = dev/'Platforms/MacOSX.platform/Developer/usr/lib'

with tempfile.TemporaryDirectory(prefix='entity-sync-') as tmp:
    main = Path(tmp)/'main.swift'
    main.write_text(source)
    binary = Path(tmp)/'tests'
    subprocess.run([
        'swiftc',
        '-F', str(frameworks), '-I', str(lib), '-L', str(lib),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        '-Xlinker', '-rpath', '-Xlinker', str(lib),
        str(main), '-o', str(binary),
    ], check=True)
    code = subprocess.run([str(binary)]).returncode

if code != 0:
    print('ПОВЕДЕНЧЕСКИЙ ТЕСТ ПРОВАЛЕН', file=sys.stderr)
    raise SystemExit(code)
print('поведенческий тест правил догона сущностей — зелёный')


# ---------------------------------------------------------------- статика
failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f'  ✓ {message}')
    else:
        failures.append(message)
        print(f'  ✗ {message}')


print('Статика: догон подключён, курсор двигается после применения')

catchup = catchup_path.read_text()
api = api_path.read_text()
app = app_path.read_text()

check('"/sync/changes"' in api, 'клиент ходит в /api/sync/changes')
check('entityChanges(since:' in api, 'клиент передаёт курсор в дельту')
check('EntitySyncCatchUp(apiClient:' in app, 'догон вызывается при переподключении')
check('recordEntityCatchUp()' in app, 'экраны заметок и рутин будит рост ревизии')
check('entityCatchUpHandlers()' in app, 'обработчики догона вынесены отдельно')
check('api.notesList()' in app, 'заметки перечитываются списком')
check('api.schedules()' in app, 'рутины перечитываются списком')

# Курсор в базе, а не в памяти: переживает перезапуск приложения.
check(
    re.search(r'static let cursorKey = "entities\.cursor"', catchup) is not None,
    'у догона свой ключ курсора',
)
check(
    re.search(r'store\.setSyncState\(Self\.cursorKey, delta\.cursor\)', catchup) is not None,
    'курсор пишется в sync_state локальной базы',
)

# Курсор двигается только когда все шаги прошли.
check(
    re.search(r'canAdvance = EntitySyncPolicy\.canAdvanceCursor\(failedSteps: failed\)', catchup)
    is not None,
    'движение курсора проверяется списком неудачных шагов',
)
check(
    re.search(r'if canAdvance \{\s*store\.setSyncState', catchup) is not None,
    'запись курсора под защитой проверки',
)

# Ошибка сети — не «успешный» догон: клиент обязан перечитать справочники.
check(
    'serverReachable: false' in catchup and 'serverReachable' in app,
    'недоступный сервер отмечен, и клиент перечитывает справочники целиком',
)

if failures:
    print(f'\nстатических проверок провалено: {len(failures)}', file=sys.stderr)
    raise SystemExit(1)
print('статические проверки — зелёные')
