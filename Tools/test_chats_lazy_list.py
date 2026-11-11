#!/usr/bin/env python3
"""Список чатов верстает строки лениво — без симулятора.

Владелец 11.11.2026: «при переходе из чатов в чаты роли идёт задержка
с появлением списка и поля ввода». Причина — `VStack` внутри `ScrollView`
в `chatScroll` строил все строки в первом кадре: в боевой базе 216 чатов,
и переход ждал эту вёрстку.

Проверка статическая: контейнер прокрутки списка обязан быть `LazyVStack`.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
path = root / "Sources/Features/Roles/RoleChatsScreen.swift"
lines = path.read_text(encoding="utf-8").splitlines()

fail = []
body_start = None
for number, line in enumerate(lines, start=1):
    if "private var chatScroll: some View" in line:
        body_start = number
        break

if body_start is None:
    fail.append("RED: не найден chatScroll")
else:
    window = lines[body_start:body_start + 12]
    joined = "\n".join(window)
    if "ScrollView {" not in joined:
        fail.append("RED: chatScroll без ScrollView")
    if "LazyVStack(spacing: 0) {" not in joined:
        fail.append(f"RED: строки списка не ленивые (ожидался LazyVStack, строка {body_start})")
    if "VStack(spacing: 0) {" in joined and "LazyVStack(spacing: 0) {" not in joined:
        fail.append("RED: остался обычный VStack")

if fail:
    print("FAIL")
    for item in fail:
        print(" -", item)
    sys.exit(1)

print(f"GREEN: список чатов ленивый (chatScroll на строке {body_start})")
