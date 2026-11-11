#!/usr/bin/env python3
"""Пометка «в работе» в названии роли и сессии — без симулятора."""
from pathlib import Path
import re, subprocess, tempfile, sys

root = Path(__file__).resolve().parents[1]
rooms = (root / "Sources/Core/Models/ChatRooms.swift").read_text()
row = (root / "Sources/Features/Roles/RoleChatListRow.swift").read_text()
screen = (root / "Sources/Features/Roles/RoleChatRoomScreen.swift").read_text()
fail = []
if "enum ChatWorkingMark" not in rooms:
    fail.append("RED: нет ChatWorkingMark")
if "ChatWorkingMark.titled" not in row:
    fail.append("RED: строка списка не ставит пометку в название")
if "Работает" in row and "turn?.running" in row:
    fail.append("RED: старая meta-строка «Работает» ещё в списке")
if "ChatWorkingMark.titled" not in screen:
    fail.append("RED: заголовок открытого чата без пометки")
block = re.search(r"public enum ChatWorkingMark \{[\s\S]*?\n\}", rooms)
if not block:
    fail.append("RED: не разобрал ChatWorkingMark")
    print("\n".join(fail) or "ok")
    sys.exit(1)
src = "import Foundation\n" + block.group(0) + """
assert(ChatWorkingMark.titled("Разработчик", running: true) == "Разработчик · в работе")
assert(ChatWorkingMark.titled("Сессия", running: false) == "Сессия")
print("GREEN 2/2")
"""
with tempfile.TemporaryDirectory(prefix="chat-working-") as tmp:
    path = Path(tmp)
    (path / "main.swift").write_text(src)
    subprocess.run(["swiftc", str(path / "main.swift"), "-o", str(path / "t")], check=True)
    r = subprocess.run([str(path / "t")], capture_output=True, text=True)
    if r.returncode != 0:
        fail.append(r.stderr or r.stdout)
if fail:
    print("\n".join(fail))
    sys.exit(1)
print("GREEN")
