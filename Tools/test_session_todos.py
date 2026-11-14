#!/usr/bin/env python3
"""Список дел агента Pi в сессиях — XCTest на macOS, без симулятора.

Собирает настоящие файлы, без копий:
`Sources/Features/Sessions/SessionTodos.swift` (разбор готового ответа сервера
и отбор ответа), модели чек-листа `Sources/Core/Models/SubtaskWorkPlan.swift`
и `Sources/Core/Models/ChatWorkPlan.swift` и тесты
`Tests/SessionTodosTests.swift`. Вид компонента здесь не проверяется — это
`ChatWorkPlanRows`, его оценивает владелец.

`--against=SHA` — те же тесты против исходников из коммита (чтобы отличить
падение из-за правки от падения, которое было и до неё). Файлов правки в
старом коммите нет — стенд отвечает кодом 2.

Коды возврата: 0 — тесты прошли; 1 — тесты упали; 2 — стенд не собрался.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
FILES = [
    'Sources/Features/Sessions/SessionTodos.swift',
    'Sources/Core/Models/SubtaskWorkPlan.swift',
    'Sources/Core/Models/ChatWorkPlan.swift',
    # ChatWorkPlan разбирает события плана через JSONValue приложения.
    'Sources/Core/Common/JSONValue.swift',
    'Tests/SessionTodosTests.swift',
]

against = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--against=')), None)


def source_text(path: str) -> str:
    """Исходник из указанного коммита или из рабочего дерева."""
    if against:
        shown = subprocess.run(['git', '-C', str(root), 'show', f'{against}:{path}'],
                               capture_output=True, text=True)
        if shown.returncode == 0:
            return shown.stdout
        print(f'ОШИБКА: {path} нет в {against} — стенд не собрать (это не падение тестов)')
        sys.exit(2)
    return (root / path).read_text()


for path in FILES:
    if not against and not (root / path).exists():
        print(f'ОШИБКА: {path} отсутствует — стенд не собрать')
        sys.exit(2)

with tempfile.TemporaryDirectory(prefix='session-todos-') as tmp_name:
    tmp = Path(tmp_name)
    for index, path in enumerate(FILES):
        (tmp / f'source{index:03d}.swift').write_text(source_text(path))
    (tmp / 'main.swift').write_text(
        'import XCTest\n'
        + '\nlet suite = SessionTodosTests.defaultTestSuite\n'
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
        print('ОШИБКА: тесты не собрались — это поломка стенда, а не результат тестов')
        sys.exit(2)
    code = subprocess.run([str(binary)]).returncode

print('GREEN: все тесты прошли' if code == 0 else f'GREEN не достигнут: тесты упали (код {code})')
sys.exit(code)
