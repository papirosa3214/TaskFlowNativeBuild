#!/usr/bin/env python3
"""Наблюдатель памяти: модель из живого каталога, не хардкод провайдеров.

Владелец 03.11.2026: под «Локальная (Ollama)» висел MiniMax, в пикере
DeepSeek/заглушки, выбор не переключался.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
src = (root / 'Sources/Features/Settings/MemoryObserverSettingsScreen.swift').read_text()

api = (root / 'Sources/Core/Networking/APIClient+ServerSettings.swift').read_text()

checks = [
    ('ModelMenu(' in src, 'экран должен выбирать модель через ModelMenu'),
    ('runtimeModels()' in src, 'каталог моделей — runtimeModels()'),
    ('models.label(forRef:' in src, 'показ — label(forRef:), как у ролей'),
    ('picked.routeRef' in src or 'routeRef' in src, 'сохраняем routeRef'),
    ('memory_observer_model' in src, 'ключ memory_observer_model'),
    ('memory_observer_enabled' in src, 'ключ memory_observer_enabled'),
    ('memory_observer_min_confidence' in src, 'ключ memory_observer_min_confidence'),
    ('embedding_model' in src, 'ключ embedding_model на экране'),
    ('memory_duplicate_similarity' in src, 'ключ memory_duplicate_similarity на экране'),
    ('memoryObserverStats' in src, 'экран грузит статистику'),
    ('memory-observer-stats' in src, 'accessibility статистики'),
    ('struct MemoryObserverStats' in api, 'DTO MemoryObserverStats'),
    ('/admin/memory-observer/stats' in api, 'API путь stats'),
    ('("local", "Локальная' not in src, 'не хардкодить провайдеров local/minimax/deepseek'),
    ('MiniMax-M3.1-Flash-Preview' not in src, 'не хардкодить MiniMax как дефолт модели'),
    ('providers = [' not in src, 'не держать статический список providers'),
]

failed = False
for ok, msg in checks:
    if not ok:
        print(f'FAIL: {msg}')
        failed = True

if re.search(r'ForEach\(\s*providers', src):
    print('FAIL: ForEach(providers) — список провайдеров должен идти из каталога')
    failed = True

# Логика resolvedModelRef — на хосте без симулятора.
marker = 'static func resolvedModelRef(raw: String, catalog: [RuntimeModel]) -> String'
if marker not in src:
    print('FAIL: нет resolvedModelRef')
    sys.exit(1)
start = src.index(marker)
opening = src.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (src[end] == '{') - (src[end] == '}')
    end += 1
helper = src[start:end]

fixture = r'''
import Foundation

struct RuntimeModel {
    let id: String
    let provider: String
    let available: Bool
    var isRoutable: Bool { true }
    var routeRef: String { "\(provider)/\(id)" }
}

extension Array where Element == RuntimeModel {
    func model(forRef ref: String) -> RuntimeModel? {
        first { $0.routeRef == ref } ?? first { $0.id == ref }
    }
}

enum MemoryObserverSettingsScreen {
''' + helper + r'''
}

func check(_ name: String, _ ok: Bool) {
    if !ok { fputs("FAIL: \(name)\n", stderr); exit(1) }
}

let catalog = [
    RuntimeModel(id: "llama3", provider: "ollama", available: true),
    RuntimeModel(id: "MiniMax-M3.1-Flash-Preview", provider: "minimax", available: true),
]
check("empty", MemoryObserverSettingsScreen.resolvedModelRef(raw: "", catalog: catalog) == "")
check("routeRef", MemoryObserverSettingsScreen.resolvedModelRef(raw: "ollama/llama3", catalog: catalog) == "ollama/llama3")
check("bare id", MemoryObserverSettingsScreen.resolvedModelRef(raw: "llama3", catalog: catalog) == "ollama/llama3")
check("unknown bare", MemoryObserverSettingsScreen.resolvedModelRef(raw: "nope", catalog: catalog) == "")
check("unknown route kept",
      MemoryObserverSettingsScreen.resolvedModelRef(raw: "xai/grok", catalog: catalog) == "xai/grok")
print("PASS: resolvedModelRef")
'''

with tempfile.TemporaryDirectory(prefix='memory-observer-') as tmp:
    path = Path(tmp)
    (path / 'main.swift').write_text(fixture)
    build = subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'run')],
                           capture_output=True, text=True)
    if build.returncode != 0:
        print('FAIL: стенд resolvedModelRef не собрался')
        print(build.stderr)
        sys.exit(1)
    run = subprocess.run([str(path / 'run')], capture_output=True, text=True)
    print(run.stdout, end='')
    if run.returncode != 0:
        print(run.stderr, end='')
        failed = True

if failed:
    sys.exit(1)
print('PASS: наблюдатель памяти читает живой каталог через ModelMenu')
