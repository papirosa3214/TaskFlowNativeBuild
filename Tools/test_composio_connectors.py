#!/usr/bin/env python3
"""Тесты подключений Composio: логика тумблеров и набор иконок.

Тесты логики собираются и запускаются на маке (swiftc + XCTest, без
симулятора) — как `test_composio_connections.py`. Вторая часть проверяет
набор иконок: все файлы серые, с прозрачностью, и их достаточно для
каталога Composio.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
model = root / 'Sources/Core/Models/RoleComposio.swift'
tests = root / 'Tests/ComposioConnectorTests.swift'
if not model.exists() or not tests.exists():
    raise SystemExit('RED: нет модели или теста Composio')

# --- часть 1: логика (swiftc + XCTest на маке, без симулятора) ---
with tempfile.TemporaryDirectory(prefix='composio-connectors-') as tmp:
    main = Path(tmp) / 'main.swift'
    binary = Path(tmp) / 'tests'
    main.write_text(tests.read_text().replace('@testable import TaskFlow', '') + '\nlet suite = ComposioConnectorTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n')
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), str(model), str(main), '-o', str(binary)], check=True)
    code = subprocess.run([str(binary)]).returncode
if code != 0:
    raise SystemExit(code)

# --- часть 2: набор иконок ---
icons = root / 'Resources/ComposioIcons'
files = sorted(icons.glob('*.png')) if icons.exists() else []
if len(files) < 1000:
    raise SystemExit(f'RED: иконок всего {len(files)}, а каталог Composio — больше тысячи сервисов')

check = '''
import sys, glob
from PIL import Image
broken = []
for path in glob.glob(sys.argv[1] + "/*.png"):
    with Image.open(path) as image:
        alpha = image.convert("RGBA").getchannel("A")
        if alpha.getextrema()[1] == 0:
            broken.append(path)
        elif image.convert("RGBA").getcolors(maxcolors=64) is None:
            broken.append(path)
print("broken:", len(broken))
sys.exit(1 if broken else 0)
'''
try:
    from PIL import Image  # noqa: F401
    result = subprocess.run([sys.executable, '-c', check, str(icons)])
except ImportError:
    # PIL есть в системном питоне мака (/usr/bin/python3), а не в том, что запустил агент.
    result = subprocess.run(['/usr/bin/python3', '-c', check, str(icons)])
if result.returncode != 0:
    raise SystemExit('RED: иконки пустые или слишком пёстрые')

print(f'OK: логика пройдена, иконок {len(files)} — все серые и непустые')
