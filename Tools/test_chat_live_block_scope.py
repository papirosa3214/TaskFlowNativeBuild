#!/usr/bin/env python3
"""Живой ход сессии: идентичность хода, реестр разметки и путь экрана — XCTest на macOS.

Собирает настоящие файлы, без копий и шимов пути:
  • `Sources/Features/Sessions/SessionLiveTurn.swift` — модель хода (`apply`, `bind`),
  • `Sources/Core/Models/ChatServerBlock.swift` — реестр блоков и идентичность хода,
  • `Sources/Chat/Feed/ChatRichContent.swift` — ключ кэша и разбор ответа,
  • модели `Sources/Core/Models` и `Sources/Core/Common` — их типы,
  • настоящий `SessionLiveReplyContent` из `SessionLiveTurnView.swift` (что экран
    передаёт в разметку),
  • тесты `Tests/ChatLiveBlockScopeTests.swift`.

Режимы:
  (по умолчанию)  GREEN на текущем дереве.
  --against=SHA   RED на явном базовом коммите: те же тесты против исходников
                  из `git show SHA:<файл>`, с `-DSESSION_TURN_BASE` (тесты
                  смены снимка требуют `bind`, которого на базе нет).
  --defect=SHA    воспроизведение заявленного дефекта сборки: назначение
                  `private(set) sessionID` вне файла модели на базе.
  --typecheck     проверка типов затронутой логики на настоящих типах:
                  `SessionSnapshot` из пакета `NewChatCore` (как в приложении)
                  и точное выражение из `SessionViewModel`
                  — `liveTurn.bind(sessionID: snapshot.id)`.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]

MODEL_DIR = 'Sources/Core/Models'
COMMON_DIR = 'Sources/Core/Common'
# AgentTrace требует TaskLiveTurn из сетевого слоя (тянется в APIClient),
# SafePasteboard — UIKit. Модели хода их не используют.
SKIP = {'Sources/Core/Models/AgentTrace.swift', 'Sources/Core/Common/SafePasteboard.swift'}

FILES = (
    sorted(f'Sources/Core/Models/{p.name}' for p in (root / MODEL_DIR).glob('*.swift'))
    + sorted(f'Sources/Core/Common/{p.name}' for p in (root / COMMON_DIR).glob('*.swift'))
    + ['Sources/Chat/Feed/ChatRichContent.swift',
       'Sources/Features/Sessions/SessionLiveTurn.swift']
)
FILES = [f for f in FILES if f not in SKIP]

tests = root / 'Tests/ChatLiveBlockScopeTests.swift'
screen = 'Sources/Features/Sessions/SessionLiveTurnView.swift'


def argument(prefix: str) -> str | None:
    for value in sys.argv[1:]:
        if value.startswith(prefix):
            return value.split('=', 1)[1]
    return None


def dev_frameworks() -> tuple[Path, Path]:
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    return frameworks, libraries


def screen_block(text: str) -> str:
    """Настоящий `enum SessionLiveReplyContent` из экрана сессии."""
    match = re.search(r'enum SessionLiveReplyContent \{.*?\n\}', text, re.S)
    if not match:
        print('RED: в SessionLiveTurnView нет SessionLiveReplyContent')
        sys.exit(1)
    return match.group(0)


def show_arguments(at: str) -> dict[str, str]:
    return {
        path: subprocess.check_output(['git', '-C', str(root), 'show', f'{at}:{path}'], text=True)
        for path in FILES + [screen]
    }


def swiftc(sources: list[Path], defines: list[str], output: Path) -> int:
    frameworks, libraries = dev_frameworks()
    command = ['swiftc',
               '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
               '-Xlinker', '-rpath', '-Xlinker', str(frameworks)]
    for define in defines:
        command += ['-D', define]
    command += [str(path) for path in sorted(sources)] + ['-o', str(output)]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr[-6000:])
    return result.returncode


def run_suite(sources: list[Path], defines: list[str], label: str) -> int:
    print(f'== {label}')
    frameworks, libraries = dev_frameworks()
    with tempfile.TemporaryDirectory(prefix='session-turn-') as tmp:
        tmp = Path(tmp)
        for index, source in enumerate(sources):
            (tmp / f'source{index:03d}.swift').write_text(source.read_text())
        (tmp / 'main.swift').write_text(
            tests.read_text()
            + '\nlet suite = ChatLiveBlockScopeTests.defaultTestSuite\n'
            + 'suite.run()\n'
            + 'exit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
        )
        binary = tmp / 'tests'
        command = ['swiftc',
                   '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
                   '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                   '-Xlinker', '-rpath', '-Xlinker', str(libraries)]
        for define in defines:
            command += ['-D', define]
        command += [str(path) for path in sorted(tmp.glob('*.swift'))] + ['-o', str(binary)]
        build = subprocess.run(command, capture_output=True, text=True)
        if build.returncode != 0:
            print(build.stderr[-6000:])
            return build.returncode
        return subprocess.run([str(binary)]).returncode


def base_defect(at: str) -> int:
    """На базе `SessionViewModel` присваивает `private(set) sessionID` — не собирается.

    Проверяем тем же компилятором на настоящем файле модели хода из этого SHA:
    назначение возможно только внутри файла, где объявлено свойство.
    """
    print(f'== база {at[:12]}: назначение sessionID вне файла модели (заявленный дефект)')
    sources = show_arguments(at)
    with tempfile.TemporaryDirectory(prefix='session-turn-defect-') as tmp:
        tmp = Path(tmp)
        for index, (path, text) in enumerate(sorted(sources.items())):
            if path == screen:
                continue
            (tmp / f'source{index:03d}.swift').write_text(text)
        (tmp / 'main.swift').write_text(
            'func assignOutsideModel(_ turn: inout SessionLiveTurn, _ sessionID: String) {\n'
            '    turn.sessionID = sessionID\n'
            '}\n'
        )
        frameworks, libraries = dev_frameworks()
        binary = tmp / 'defect'
        build = subprocess.run([
            'swiftc', '-typecheck',
            '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
            *[str(path) for path in sorted(tmp.glob('*.swift'))],
        ], capture_output=True, text=True)
        print(build.stderr[-2500:])
        if build.returncode == 0:
            print('ожидался отказ компиляции, но назначение прошло')
            return 1
        print('дефект воспроизведён: компилятор не даёт назначить sessionID снаружи модели')
        return 0


against = argument('--against=')
defect = argument('--defect=')


def model_tail(path: str = 'Sources/Features/Sessions/Engine/SessionViewModel.swift') -> str:
    """Настоящий хвост модели экрана: `extension NewChatCore.JSONValue` с `foundationValue`.

    `SessionLiveTurn` берёт `SessionJSON = NewChatCore.JSONValue` и пользуется
    `foundationValue`; расширение живёт в файле модели экрана, который целиком в
    отдельном компиляторе не собирается (сеть, хранилище, UIKit).
    """
    text = (root / path).read_text()
    index = text.find('extension NewChatCore.JSONValue {')
    if index < 0:
        print('RED: в SessionViewModel нет extension NewChatCore.JSONValue')
        sys.exit(1)
    return 'import Foundation\nimport NewChatCore\n\n' + text[index:]


def typecheck() -> int:
    """Проверка типов: реальный `SessionSnapshot` пакета и выражение из модели экрана.

    `SessionViewModel` целиком требует сети, хранилища и UIKit, поэтому в
    отдельном компиляторе не собирается. Здесь проверяются его изменённая
    строка (с настоящими типами) и весь файл тестов на настоящих компонентах.
    """
    print('== проверка типов: SessionSnapshot из NewChatCore + bind в модели хода')
    with tempfile.TemporaryDirectory(prefix='session-turn-types-') as tmp:
        tmp = Path(tmp)
        package = sorted(str(path) for path in (root / 'Packages/NewChatCore/Sources/NewChatCore').glob('*.swift'))
        module = tmp / 'NewChatCore.swiftmodule'
        build = subprocess.run(['swiftc', '-emit-module', '-module-name', 'NewChatCore',
                                '-swift-version', '5', '-emit-module-path', str(module), *package],
                               capture_output=True, text=True)
        if build.returncode != 0:
            print(build.stderr[-4000:])
            return build.returncode
        for index, path in enumerate(FILES):
            (tmp / f'source{index:03d}.swift').write_text((root / path).read_text())
        (tmp / 'screen.swift').write_text(screen_block((root / screen).read_text()))
        (tmp / 'json-tail.swift').write_text(model_tail())
        (tmp / 'call-site.swift').write_text(
            'import Foundation\nimport NewChatCore\n\n'
            '// Точное выражение из SessionViewModel.installSnapshot.\n'
            'func installLiveTurn(from snapshot: SessionSnapshot, into turn: inout SessionLiveTurn) {\n'
            '    turn.bind(sessionID: snapshot.id)\n'
            '}\n'
        )
        (tmp / 'tests.swift').write_text(tests.read_text())
        frameworks, libraries = dev_frameworks()
        check = subprocess.run([
            'swiftc', '-typecheck', '-I', str(tmp),
            '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
            *sorted(str(path) for path in tmp.glob('*.swift')),
        ], capture_output=True, text=True)
        print(check.stderr[-4000:].strip() or 'ошибок типов нет')
        return check.returncode


if '--typecheck' in sys.argv:
    sys.exit(typecheck())

if defect:
    sys.exit(base_defect(defect))

if against:
    sources = show_arguments(against)
    current = [root / path for path in FILES]
    with tempfile.TemporaryDirectory(prefix='session-turn-red-') as tmp:
        tmp = Path(tmp)
        for index, path in enumerate(FILES):
            (tmp / f'source{index:03d}.swift').write_text(sources[path])
        (tmp / f'screen{len(FILES):03d}.swift').write_text(screen_block(sources[screen]))
        code = run_suite(sorted(tmp.glob('*.swift')), ['SESSION_TURN_BASE'],
                         f'RED — исходники {against[:12]} (область по сессии и секунде)')
    # 0 здесь означал бы, что тесты на базе проходят: RED не воспроизведён.
    sys.exit(0 if code != 0 else 1)

with tempfile.TemporaryDirectory(prefix='session-turn-green-') as tmp:
    tmp = Path(tmp)
    for index, path in enumerate(FILES):
        (tmp / f'source{index:03d}.swift').write_text((root / path).read_text())
    (tmp / f'screen{len(FILES):03d}.swift').write_text(screen_block((root / screen).read_text()))
    code = run_suite(sorted(tmp.glob('*.swift')), [],
                     'GREEN — идентичность хода и ключ кэша по содержимому')
sys.exit(code)
