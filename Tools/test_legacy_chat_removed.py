#!/usr/bin/env python3
"""Мёртвый чат удалён, живой путь цел.

Проверки исходников на хосте, не UI-тест. Мёртвый кластер — старый чат
(`ChatScreen` и его обвязка): ссылок из живого кода нет, чат в приложении
один — `RoleChatsScreen`. Живой путь (лента ролей, полосы дат, модели
`ApiChatMessage`/`ChatChannel`) обязан остаться невредимым.

RED: на дереве до удаления падает (файлы на месте).
GREEN: после удаления проходит.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

DEAD_FILES = [
    'Sources/Features/Chat/ChatScreen.swift',
    'Sources/Features/Chat/ChatViewModel.swift',
    'Sources/Features/Chat/ChatComposer.swift',
    'Sources/Features/Chat/TypingLine.swift',
    'Sources/Features/Chat/ChatBubble.swift',
    'Sources/Features/Chat/ChatAPI.swift',
    'Sources/Core/Networking/APIClient+Chat.swift',
    'Tests/ChatViewModelTests.swift',
]

DEAD_TYPES = [
    'struct ChatScreen',
    'final class ChatViewModel',
    'struct ChatBubble',
    'struct ChatComposer',
    'struct TypingLine',
    'struct ChatStatsSheetContent',
]

failures: list[str] = []


def check(condition: bool, name: str) -> None:
    if not condition:
        failures.append(name)


for name in DEAD_FILES:
    check(not (ROOT / name).exists(), 'мёртвый файл на месте: ' + name)

sources = ''
for path in (ROOT / 'Sources').rglob('*.swift'):
    sources += path.read_text(errors='ignore')
for dead in DEAD_TYPES:
    # Граница слова: `struct ChatComposerControlsView` — живой, а не мёртвый
    # `struct ChatComposer`.
    check(re.search(re.escape(dead) + r'\b', sources) is None,
          'мёртвый тип в Sources: ' + dead)

screen = (ROOT / 'Sources/Features/Roles/RoleChatsScreen.swift').read_text()
check('.scrollPosition($chatScrollPosition)' in screen,
      'живой чат потерял привязку позиции ленты')
check('.defaultScrollAnchor(chatFollowsBottom ? .bottom : nil, for: .sizeChanges)' in screen,
      'живой чат потерял удержание низа')

marks = (ROOT / 'Sources/ChatComponents/Feed/ChatFeedMarks.swift').read_text()
check('ChatDayLabel' in marks and 'ChatFeedDivider' in marks,
      'ChatFeedMarks.swift удалён, а он живой (даты и разделители в ленте)')

model = (ROOT / 'Sources/Core/Models/Chat.swift').read_text()
check('struct ApiChatMessage' in model and 'enum ChatChannel' in model,
      'живые модели чата (ApiChatMessage, ChatChannel) задеты')
check('ApiChatStats' not in model, 'остатки статистики мёртвого чата в Chat.swift')

baseline = (ROOT / 'Tools/design-system-baseline.txt').read_text()
check('ChatScreen.swift' not in baseline, 'в снимке дизайн-системы остался удалённый экран')

render = (ROOT / 'Tests/RoleReplyRenderTests.swift').read_text()
check('ChatBubble.swift' not in render, 'тест рендера ссылается на удалённый ChatBubble')

# Пережившие удаление части ленты: точки «печатает…» и вложения нужны живому
# чату и карточке задачи. Раньше они лежали в удалённых файлах.
parts = ROOT / 'Sources/ChatComponents/Feed/ChatFeedParts.swift'
check(parts.exists(), 'части ленты (точки «печатает», вложения) потеряны')
if parts.exists():
    text = parts.read_text()
    for needed in ('struct TypingDot', 'struct ChatAttachmentImage', 'struct ChatFileChip'):
        check(needed in text, 'часть ленты потеряна: ' + needed)

if failures:
    for name in failures:
        print('FAIL ' + name)
    sys.exit(1)
print('Мёртвый чат удалён, живой путь цел: PASS')
