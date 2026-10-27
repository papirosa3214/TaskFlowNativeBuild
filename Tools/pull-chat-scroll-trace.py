#!/usr/bin/env python3
"""Забрать записи прокрутки чата с iPhone и найти скачки ленты.

Запуск: python3 Tools/pull-chat-scroll-trace.py [--device <имя|UDID>] [--since HH:MM]
Файлы кладутся в build_sim/chat-scroll-trace/ (в git не попадают:
build_sim в .gitignore). Нужен подключённый iPhone с DEBUG-сборкой.

Скачок — сдвиг ленты больше 40 pt между соседними замерами, пока владелец
её не трогает (фаза idle): это программная прокрутка, а не жест.
"""
import argparse, json, subprocess, tempfile
from datetime import datetime
from pathlib import Path

BUNDLE = 'com.maksim.taskflow.native'
root = Path(__file__).resolve().parents[1]
out = root / 'build_sim' / 'chat-scroll-trace'

def first_device():
    with tempfile.NamedTemporaryFile(suffix='.json') as tmp:
        subprocess.run(['xcrun', 'devicectl', 'list', 'devices', '--json-output', tmp.name],
                       check=True, capture_output=True)
        devices = json.load(open(tmp.name))['result']['devices']
    phones = [d for d in devices if d.get('hardwareProperties', {}).get('platform') == 'iOS'
              and d.get('connectionProperties', {}).get('tunnelState') != 'unavailable']
    if not phones:
        raise SystemExit('iPhone не найден: подключи его к маку')
    return phones[0]['identifier']

def pull(device):
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', device,
                    '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE,
                    '--source', 'Library/Application Support/ChatScrollDiagnostics',
                    '--destination', str(out)], check=True, capture_output=True)

def analyse(since):
    files = sorted(out.rglob('session-*.json'))
    print(f'сеансов: {len(files)}')
    for path in files:
        entries = json.load(open(path))
        jumps = []
        for a, b in zip(entries, entries[1:]):
            if b.get('event'):
                continue
            dy = b['geometry']['offsetY'] - a['geometry']['offsetY']
            ctx = b.get('context', {})
            if abs(dy) > 40 and ctx.get('phase', 'idle') == 'idle':
                jumps.append((b, dy))
        if not jumps:
            continue
        print(f'\n{path.name}: скачков {len(jumps)}')
        for b, dy in jumps[:15]:
            t = datetime.fromtimestamp(b.get('wallTime', 0))
            if since and t.strftime('%H:%M') < since:
                continue
            ctx = b.get('context', {})
            print(f"  {t:%H:%M:%S}  сдвиг {dy:+.0f} pt  клавиатура {ctx.get('keyboardHeight', 0):.0f}"
                  f"  фокус {'да' if ctx.get('composerFocused') else 'нет'}"
                  f"  строки {'менялись' if b['rowsChanged'] else 'те же'}  у низа {'да' if b['nearBottom'] else 'нет'}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--device')
    parser.add_argument('--since', help='показывать скачки начиная с HH:MM')
    parser.add_argument('--no-pull', action='store_true', help='только разбор уже забранного')
    args = parser.parse_args()
    if not args.no_pull:
        pull(args.device or first_device())
    analyse(args.since)
