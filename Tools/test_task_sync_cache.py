#!/usr/bin/env python3
"""Проверка правил синхронизации кэша задач на macOS — без симулятора.

Гоняет настоящие правила (`Sources/Core/Store/TaskSyncCachePolicy.swift`) и
настоящие тесты (`Tests/TaskSyncCachePolicyTests.swift`) на macOS: файл правил
не тянет ни БД, ни сети, поэтому собирается swiftc без симулятора.

Дополнительно — СТАТИЧЕСКАЯ проверка структуры записи (не замена поведенческому
тесту, а страховка от возврата к прежней схеме «отпечаток отдельно от тела»):
  * `LocalStore.applyTaskList` — тело, отпечаток и курсор пишутся ОДНОЙ
    транзакцией;
  * `LocalStore.applyTaskDelta` — карточки, удаления и курсор — ОДНОЙ
    транзакцией;
  * `TaskStore.load` не пишет отпечаток мимо транзакции.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
policy_path = root/'Sources/Core/Store/TaskSyncCachePolicy.swift'
tests_path = root/'Tests/TaskSyncCachePolicyTests.swift'
store_path = root/'Sources/Core/Store/LocalStore.swift'
task_store_path = root/'Sources/Core/Stores/TaskStore.swift'

for path in (policy_path, tests_path, store_path, task_store_path):
    if not path.exists():
        raise SystemExit(f"нет файла: {path}")

policy = policy_path.read_text()
tests = (tests_path.read_text()
         .replace('@testable import TaskFlow', '')
         .replace('    func test', '    @objc func test'))

source = policy + '\n' + tests + '\n'
source += '''
let suites = [TaskSyncCachePolicyTests.defaultTestSuite]
for suite in suites { suite.run() }
exit(suites.allSatisfy { $0.testRun!.hasSucceeded } ? 0 : 1)
'''

dev = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = dev/'Platforms/MacOSX.platform/Developer/Library/Frameworks'
lib = dev/'Platforms/MacOSX.platform/Developer/usr/lib'

with tempfile.TemporaryDirectory(prefix='task-sync-cache-') as tmp:
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
print('поведенческий тест правил синхронизации — зелёный')


# ---------------------------------------------------------------- статика
def body_of(text: str, signature: str) -> str:
    start = text.index(signature)
    opening = text.index('{', start)
    depth = 0
    end = opening
    while True:
        if text[end] == '{':
            depth += 1
        elif text[end] == '}':
            depth -= 1
            if depth == 0:
                break
        end += 1
    return text[opening:end + 1]


store = store_path.read_text()
task_store = task_store_path.read_text()

problems = []

apply_list = body_of(store, 'func applyTaskList(')
if apply_list.count('queue.write') != 1:
    problems.append('applyTaskList: транзакция должна быть одна, а их %d' % apply_list.count('queue.write'))
for key in ('tasksETag', 'tasksCursor'):
    if key not in apply_list:
        problems.append(f'applyTaskList: {key} пишется не в этой транзакции')

apply_delta = body_of(store, 'func applyTaskDelta(')
if apply_delta.count('queue.write') != 1:
    problems.append('applyTaskDelta: транзакция должна быть одна, а их %d' % apply_delta.count('queue.write'))
if 'tasksCursor' not in apply_delta:
    problems.append('applyTaskDelta: курсор пишется не в этой транзакции')

load_body = body_of(task_store, 'public func load(')
# Сброс отпечатка (nil) — часть восстановления после 304 без тела, он
# разрешён. Запрещено писать НОВЫЙ отпечаток мимо транзакции с телом.
etag_writes = re.findall(r'setSyncState\(\s*SyncStateKeys\.tasksETag\s*,\s*([^\)]*)\)', load_body)
new_etag_writes = [value for value in etag_writes if value.strip() != 'nil']
if new_etag_writes:
    problems.append('load: новый отпечаток пишется мимо транзакции с телом')
if 'applyTaskList(' not in load_body:
    problems.append('load: тело, отпечаток и курсор должны писаться applyTaskList')

if problems:
    for line in problems:
        print('СТАТИЧЕСКАЯ ПРОВЕРКА: ' + line, file=sys.stderr)
    raise SystemExit(1)
print('статическая проверка структуры записи — чисто')
