#!/usr/bin/env python3
"""Ответ роли в JSON-конверте показывается один раз.

Проверка на хосте (без симулятора): собирает настоящий код
`RoleChatLiveTurn.completed(with:)`, `itemsWithoutAnswerText(for:)` и
`withoutFlattenedAnswer(_:)` из `Sources/Core/Models/RoleChat.swift`
и проверяет на живых значениях:

1. Ответ с конвертом (`role_envelope`) — в закрытом ходе не остаётся
   плоской копии ответа (таблица markdown, виджет сырым JSON), а действия
   и промежуточные реплики хода остаются.
2. Строка готового сообщения для ответа-конверта не печатает плоскую
   копию ответа рядом с нативными блоками.
3. Обычный ответ без конверта не теряет текст (регресс).

Запуск: python3 Tools/test_chat_envelope_answer_once.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
model = (root / 'Sources/Core/Models/RoleChat.swift').read_text()
from chat_screen_sources import read_chat_screen
screen = read_chat_screen(root)


def method(text: str, signature: str) -> str:
    if signature not in text:
        print('FAIL: в RoleChat.swift нет метода ' + signature)
        raise SystemExit(1)
    a = text.index(signature)
    b = text.index('{', a)
    depth = 1
    end = b + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[a:end]


completed = method(model, 'func completed(with message: RoleChatMessage) -> Self')
without_text = method(model, 'func itemsWithoutAnswerText(for message: RoleChatMessage) -> [RoleChatLiveItem]')
without_flat = method(model, 'static func withoutAnswerText(_ items: [RoleChatLiveItem],')

fixture = '''import Foundation

struct Action { let id: String }

enum RoleChatLiveItem {
    case text(String)
    case step(Action)
    case thinking(Action)
    var id: String {
        switch self {
        case .text(let t): return "text-" + t
        case .step(let s): return s.id
        case .thinking(let t): return t.id
        }
    }
    var isText: Bool { if case .text = self { return true }; return false }
}

struct Steps { let items: [RoleChatLiveItem] }

struct RoleChatMessage {
    let text: String
    let steps: Steps?
    let hasStructuredAnswer: Bool
}

struct Turn {
    let chatID: String
    let userID: String
    let name: String
    let startedAt: String?
    let items: [RoleChatLiveItem]
    let thinking: String?
    let triggerMessageID: String?

''' + completed + '''

''' + without_text + '''

''' + without_flat + '''

    init(chatID: String, userID: String, name: String, startedAt: String?,
         items: [RoleChatLiveItem], thinking: String?, triggerMessageID: String?) {
        self.chatID = chatID
        self.userID = userID
        self.name = name
        self.startedAt = startedAt
        self.items = items
        self.thinking = thinking
        self.triggerMessageID = triggerMessageID
    }
}

func texts(_ items: [RoleChatLiveItem]) -> [String] {
    items.compactMap { if case .text(let t) = $0 { return t }; return nil }
}

func stepIDs(_ items: [RoleChatLiveItem]) -> [String] {
    items.compactMap { if case .step(let s) = $0 { return s.id }; return nil }
}

let step = Action(id: "s1")
// Плоская копия ответа, которую сервер кладёт в `message.text`.
let flatAnswer = "Готово\\n\\n```widget\\n{\\"type\\":\\"table\\"}\\n```"
// Живой ход: текст блока ответа, шаг, реплика хода и вся плоская копия.
let live = Turn(chatID: "c", userID: "u", name: "N", startedAt: nil,
                items: [.text("Готово"), .step(step), .text("сейчас проверю"), .text(flatAnswer)],
                thinking: nil, triggerMessageID: nil)

// 1. Ответ-конверт: в закрытом ходе плоской копии ответа быть не должно.
let structured = RoleChatMessage(
    text: flatAnswer,
    steps: Steps(items: [.step(step)]),
    hasStructuredAnswer: true)
let closed = live.completed(with: structured)
let closedTexts = texts(closed.items)
if closedTexts != ["сейчас проверю"] {
    print("FAIL: в закрытом ходе ожидалась только промежуточная реплика, получено: \\(closedTexts)")
    exit(1)
}
if stepIDs(closed.items) != ["s1"] {
    print("FAIL: действия хода потерялись: \\(stepIDs(closed.items))")
    exit(1)
}

// 2. Строка готового сообщения: плоской копии ответа рядом с блоками нет.
let row = live.itemsWithoutAnswerText(for: structured)
if row.contains(where: { $0.isText }) == false {
    print("FAIL: в строке готового сообщения потерялась промежуточная реплика хода")
    exit(1)
}
if texts(row) != ["сейчас проверю"] {
    print("FAIL: в строке готового сообщения ожидалась только промежуточная реплика, получено: \\(texts(row))")
    exit(1)
}
if stepIDs(row) != ["s1"] {
    print("FAIL: в строке готового сообщения потерялись действия: \\(stepIDs(row))")
    exit(1)
}

// 3. Обычный ответ без конверта: текст на месте, ровно один раз.
let plain = RoleChatMessage(
    text: "Ответ роли целиком",
    steps: Steps(items: [.step(step), .text("сейчас проверю")]),
    hasStructuredAnswer: false)
let plainClosed = live.completed(with: plain)
if texts(plainClosed.items) != ["Ответ роли целиком"] {
    print("FAIL: обычный ответ потерял или продублировал текст: \\(texts(plainClosed.items))")
    exit(1)
}
if texts(live.itemsWithoutAnswerText(for: plain)) != ["Готово", "сейчас проверю", flatAnswer] {
    print("FAIL: обычный ответ без конверта потерял текст в строке сообщения")
    exit(1)
}

print("PASS: ответ-конверт показывается один раз, обычный ответ не потерян")
'''

with tempfile.TemporaryDirectory(prefix='chat-envelope-once-') as d:
    p = Path(d)
    (p / 'main.swift').write_text(fixture)
    build = subprocess.run(['swiftc', str(p / 'main.swift'), '-o', str(p / 'run')])
    if build.returncode != 0:
        print('FAIL: тестовый стенд не собрался')
        raise SystemExit(build.returncode)
    run = subprocess.run([str(p / 'run')])
    if run.returncode != 0:
        raise SystemExit(run.returncode)

# Экран чата обязан брать пункты закрытого хода через фильтр, а не напрямую.
import re
direct = re.search(r'closedTurnItems\[message\.id\] = (turn|parked)\.items\s*$', screen, re.M)
if direct:
    print('FAIL: экран чата берёт пункты хода напрямую — плоская копия ответа вернётся в строку')
    raise SystemExit(1)
if screen.count('itemsWithoutAnswerText(for: message)') < 2:
    print('FAIL: экран чата не фильтрует пункты хода через itemsWithoutAnswerText(for:)')
    raise SystemExit(1)
print('PASS: экран чата фильтрует пункты закрытого хода')
