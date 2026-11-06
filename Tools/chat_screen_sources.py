"""Исходники экрана чата одним текстом — для проверок, которые ищут в нём строки.

06.11.2026 `RoleChatsScreen.swift` (4078 строк) разбит на файлы по типам
(владелец: «основной чат раздробить на составляющие»). Проверки раньше читали
один файл; теперь читают все части вместе, и искать в тексте можно как прежде.
"""
from pathlib import Path

CHAT_SCREEN_FILES = [
    "RoleChatsScreen.swift",
    "RoleChatRoomScreen.swift",
    "RoleChatRoomLoader.swift",
    "RoleChatListRow.swift",
    "RoleChatStepLine.swift",
    "RoleChatCreateScreen.swift",
    "RoleChatDetailsSheet.swift",
    "RoleChatVoiceBubble.swift",
    "RoleChatAvatar.swift",
]


def read_chat_screen(root) -> str:
    folder = Path(root) / "Sources" / "Features" / "Roles"
    return "\n".join((folder / name).read_text(encoding="utf-8") for name in CHAT_SCREEN_FILES)
