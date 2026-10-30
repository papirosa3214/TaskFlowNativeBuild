#!/usr/bin/env python3
"""Живой ход не укорачивается — иначе лента шатается вверх-вниз.

Проверка логики на хосте: правило `RoleLiveTurnGrowth` берётся из настоящего
исходника `Sources/Core/Models/RoleChat.swift` и прогоняется swiftc'ом, без
симулятора. Плюс проверки исходника экрана по тем местам, которые ломали
высоту строки (разбор 25-26.10.2026, `docs/2026-10-25-chat-window-behaviour.md`).

Живой случай (30.10.2026): ход роли идёт 7 минут, снимки приходят каждые
150 мс, а после любого сообщения в чате клиент перезапрашивает снимок хода.
Снимок может прийти позже дельт — и тогда в нём меньше пунктов, чем уже
видно. Если такой снимок принять, пузырь схлопывается, лента держится за низ
и уезжает вниз, а потом возвращается, когда пункты проявятся заново.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCREEN = (ROOT / 'Sources/Features/Chat/RoleChatsScreen.swift').read_text()
BUBBLE = (ROOT / 'Sources/Features/Chat/RoleLiveTurnView.swift').read_text()
MODEL = (ROOT / 'Sources/Core/Models/RoleChat.swift').read_text()


def block(text: str, marker: str) -> str:
    start = text.index(marker)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


MAIN = r'''
import Foundation

var failures: [String] = []

func expect(_ name: String, _ got: Bool, _ want: Bool) {
    if got != want { failures.append(name + ": got " + String(got) + " want " + String(want)) }
}

// 1. Снимок с теми же действиями — принимаем.
expect("same actions accepted",
       RoleLiveTurnGrowth.accepts(shown: ["step:1", "step:2"], incoming: ["step:1", "step:2"]), true)

// 2. Ход вырос — принимаем.
expect("growth accepted",
       RoleLiveTurnGrowth.accepts(shown: ["step:1"], incoming: ["step:1", "step:2", "step:3"]), true)

// 3. Снимок потерял показанное действие — НЕ принимаем (это и было шатание).
expect("snapshot that drops a shown action is rejected",
       RoleLiveTurnGrowth.accepts(shown: ["step:1", "step:2", "step:3"],
                                  incoming: ["step:1", "step:3"]), false)

// 4. Пустой снимок при показанном ходе — тоже не принимаем.
expect("empty snapshot rejected", RoleLiveTurnGrowth.accepts(shown: ["step:1"], incoming: []), false)

// 5. Законченный ход: список заменяется содержимым готового ответа.
expect("final snapshot replaces the list",
       RoleLiveTurnGrowth.accepts(shown: ["step:1", "step:2"], incoming: ["step:1"], isFinal: true), true)

// 6. Ничего не показано — принимать нечего терять.
expect("first snapshot accepted", RoleLiveTurnGrowth.accepts(shown: [], incoming: ["step:1"]), true)

if failures.isEmpty { print("Live turn growth rule: PASS (6)"); exit(0) }
for failure in failures { print("FAIL " + failure) }
exit(1)
'''

source = 'import Foundation\n' + block(MODEL, 'enum RoleLiveTurnGrowth {')
with tempfile.TemporaryDirectory(prefix='chat-live-growth-') as folder:
    main = Path(folder) / 'main.swift'
    main.write_text(source + MAIN)
    binary = Path(folder) / 'run'
    subprocess.run(['swiftc', str(main), '-o', str(binary)], check=True)
    if subprocess.run([str(binary)]).returncode != 0:
        raise SystemExit(1)


failures: list[str] = []


def check(condition: bool, name: str) -> None:
    if not condition:
        failures.append(name)


# Пейсер принимает снимок через правило, а законченный ход — без правила.
ingest = block(MODEL, 'mutating func ingest(')
check('RoleLiveTurnGrowth.accepts(' in ingest and 'isFinal' in ingest,
      'пейсер не принимает снимок, который теряет показанные действия')

bubble = block(BUBBLE, 'private func ingest(')
check('isFinal: isComplete' in bubble,
      'законченному ходу список заменяется без правила роста')

# Готовый ответ, закрывший живой ход, рисует шаги той же формы, что пузырь.
check(SCREEN.count('if let items = closedTurnItems[message.id]') >= 2
      and SCREEN.count('showsActionPreview: true)') >= 2,
      'готовое сообщение рисует шаги тем же составом и формой, что живой пузырь')

# Строка «В ответ на» больше не ищет вопрос перебором всей ленты.
context = block(SCREEN, 'private func replyContext(')
check('messages.first(where:' not in context,
      'нет квадратичного поиска вопроса в каждой строке')
check('let replyExcerpts = Self.replyExcerpts(from: messages)' in SCREEN,
      'выдержки считаются один раз на кадр')

# --- Лента и прокрутка: правила, из-за которых она шаталась (ревью 30.10) ---

feed = block(SCREEN, 'private var messageScroll: some View')
check('.animation(' not in feed,
      'контейнер ленты всё ещё анимирует свои изменения — пружина перецеливается на каждой дельте')

send_block = block(SCREEN, 'private func send() async')
send_code = '\n'.join(l for l in send_block.splitlines() if not l.strip().startswith('//'))
check('scrollTo(' not in send_code and 'withAnimation' not in send_code,
      'отправка снова тянет ленту двумя механизмами сразу')

completed = block(MODEL, 'func completed(with message: RoleChatMessage) -> Self')
check('merged.append' in completed and '(message.steps?.items ?? []) +' not in completed,
      'на закрытии хода список пунктов подменяется, а не дополняется — пузырь проседает')

line = next((l for l in SCREEN.splitlines() if 'if let previous = liveTurns[userID], previous.playbackID != turn.playbackID' in l), '')
show = block(SCREEN, 'private func showLiveTurn(')
check('mergeLiveTurn(turn, over: previous)' in show,
      'снимок с другим временем начала пересоздаёт ход вместо слияния')

snapshot = block(SCREEN, 'private func loadLiveTurns() async')
check('mergeLiveTurn(turn, over: old)' in snapshot,
      'снимок хода подменяет показанное без слияния')

segments = block(SCREEN.replace(SCREEN, SCREEN), 'private var messageScroll: some View')  # заглушка
segment_ids = (ROOT / 'Sources/Features/Chat/RoleActionGroup.swift').read_text()
check('static func identities(' in segment_ids,
      'куски живого пузыря снова идентифицируются по номеру — пересоздание от прихода текста')
view = (ROOT / 'Sources/Features/Chat/RoleLiveTurnView.swift').read_text()
check('RoleLiveSegment.identities(segments)' in view and 'id: \\.offset' not in view,
      'список кусков живого пузыря всё ещё по индексу')

if failures:
    for name in failures:
        print('FAIL ' + name)
    raise SystemExit(1)
print('Chat live turn height: PASS (4)')
