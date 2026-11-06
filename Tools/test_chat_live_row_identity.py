#!/usr/bin/env python3
"""Строка живого хода не пересоздаётся, когда ход заканчивается.

Владелец 06.11.2026: длинный ответ «всё сразу ляпнулся». Причина: идущий ход
и доигрывающий (ответ уже пришёл, текст ещё печатается) рисовались разными
ветками `if/else` ленты. Для SwiftUI это разные вью: очередь печати пузыря
терялась, новый пузырь видел законченный ход и показывал текст целиком.
Проверка: в ленте одна ветка для обоих состояний, и доигрывающий ход
передаётся в `RoleChatLiveSlotView`. Путь к экрану — аргументом (для RED).
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tools'))
from chat_screen_sources import read_chat_screen

screen = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else read_chat_screen(ROOT)
failures = []
if 'if let turn = item.completingTurn' in screen:
    failures.append('доигрывающий ход рисуется отдельной веткой ленты')
if 'completing: item.completingTurn' not in screen:
    failures.append('RoleChatLiveSlotView не получает доигрывающий ход')
if failures:
    print('FAIL: ' + '; '.join(failures))
    raise SystemExit(1)
print('Live row identity: PASS')
