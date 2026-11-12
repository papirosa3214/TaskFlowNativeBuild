#!/usr/bin/env python3
"""Нижняя панель вкладок не показывается на экранах переписки.

Зачем (владелец 12.11.2026: «убери из чата панель меню таб бар, а то панель
ввода текста наложились на него»): панель вкладок висела поверх панели ввода
в комнате чата. Правило одно и проверяется здесь:

  • панель прячется от любого открытого экрана переписки, а не только на
    вкладке «Чат» и не только по глубине пути;
  • признак «экран переписки открыт» — множество держателей, а не один флаг:
    закрытие вложенного экрана не снимает скрытие у родительского;
  • системный таббар прячется на подэкранах независимо от того, включена
    пилюля или нет.

Запуск:
    python3 Tools/test_chat_tab_bar.py              # текущее дерево
    python3 Tools/test_chat_tab_bar.py --ref <коммит>   # старая редакция
"""

from __future__ import annotations

import argparse
import subprocess
import sys

ROOT = "Sources"

FILES = {
    "root": "Sources/App/Navigation/RootShellView.swift",
    "state": "Sources/Features/Roles/ChatSectionState.swift",
    "room": "Sources/Features/Roles/RoleChatRoomScreen.swift",
    "section": "Sources/Features/Roles/RoleChatsScreen.swift",
    "session": "Sources/Features/Sessions/OwnerSessionScreen.swift",
    "taskchat": "Sources/Features/Tasks/TaskChatSheet.swift",
}


def read(path: str, ref: str | None) -> str:
    if ref is None:
        with open(path, encoding="utf-8") as f:
            return f.read()
    try:
        return subprocess.run(
            ["git", "show", f"{ref}:{path}"],
            check=True, capture_output=True, text=True,
        ).stdout
    except subprocess.CalledProcessError:
        return ""


def check(texts: dict[str, str]) -> list[str]:
    problems: list[str] = []

    root = texts["root"]
    if "selectedTab == .chat && ChatSectionState.shared.isNested" in root:
        problems.append("панель прячется только на вкладке «Чат» — экран переписки из карточки задачи не учтён")
    if "!ChatSectionState.shared.isNested" not in root:
        problems.append("пилюля не спрашивает признак «экран переписки открыт»")
    if "isPillTabBarEnabled && (quickAddDraft" in root:
        problems.append("системный таббар прячется только при включённой пилюле")

    state = texts["state"]
    for needle in ("func hold(", "func release(", "Set<String>"):
        if needle not in state:
            problems.append(f"состояние раздела не держит множество экранов: нет `{needle}`")
    if "func setNested(" in state:
        problems.append("в состоянии раздела остался булев флаг `setNested`")

    for key, label in (("room", "комната чата"), ("taskchat", "чат карточки")):
        body = texts[key]
        if "ChatSectionState.shared.hold(" not in body or "ChatSectionState.shared.release(" not in body:
            problems.append(f"{label} не сообщает о себе нижней панели")
    for key, label in (("section", "раздел «Чаты»"), ("session", "сессия владельца")):
        if "ChatSectionState.shared.hold(" not in texts[key]:
            problems.append(f"{label} не держит скрытие панели")

    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", default=None, help="проверить редакцию коммита вместо дерева")
    args = parser.parse_args()

    texts = {key: read(path, args.ref) for key, path in FILES.items()}
    missing = [path for key, path in FILES.items() if not texts[key]]
    if missing:
        print("нет файлов: " + ", ".join(missing))
        return 2

    problems = check(texts)
    if problems:
        print(f"нижняя панель: {len(problems)} замечание(й)")
        for item in problems:
            print(f"  • {item}")
        return 1

    print("нижняя панель: OK — прячется на всех экранах переписки")
    return 0


if __name__ == "__main__":
    sys.exit(main())
