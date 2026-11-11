#!/usr/bin/env python3
"""Список чатов не трогает локальную базу на главном потоке — без симулятора.

Владелец 11.11.2026: «при переходе на эти экраны поле ввода поиска… задержка
какая-то идёт». Причина — чтение и запись GRDB прямо в главном потоке при
открытии экрана: переход и штатное поле поиска в шапке ждут базу.

Проверка статическая: каждый вызов `LocalStore.` в `RoleChatsScreen.swift`
обязан стоять внутри блока `Task.detached`.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
path = root / "Sources/Features/Roles/RoleChatsScreen.swift"
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

fail = []
current_func = None
func_has_detached = False
for number, line in enumerate(lines, start=1):
    stripped = line.strip()
    if stripped.startswith("private func ") or stripped.startswith("func "):
        current_func = stripped.split("(")[0].replace("private func ", "").replace("func ", "")
        func_has_detached = False
    if "Task.detached" in line:
        func_has_detached = True
    if "LocalStore." in line and not func_has_detached:
        fail.append(f"строка {number}: LocalStore в главном потоке (функция {current_func})")

# Раньше база читалась прямо в load()/refreshList() — жалоба была именно про них.
if "private func localChats(" not in text:
    fail.append("RED: нет фонового чтения localChats")
if "private func storeChats(" not in text:
    fail.append("RED: нет фоновой записи storeChats")
# Дисковый кэш ответов (`ResponseCache`, `Data(contentsOf:)`) — тоже в фоне.
if "api.cachedRoleChats(" in text or "api.cachedChatRooms(" in text:
    fail.append("RED: дисковый кэш ответов читается прямо в главном потоке")

if fail:
    print("FAIL")
    for item in fail:
        print(" -", item)
    sys.exit(1)

print(f"GREEN: LocalStore только в фоне ({sum(1 for l in lines if 'LocalStore.' in l)} вызовов)")
