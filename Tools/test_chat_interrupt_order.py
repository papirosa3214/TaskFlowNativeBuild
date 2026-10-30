#!/usr/bin/env python3
"""Порядок ленты, когда владелец пишет во время хода роли.

Проверка логики на хосте: `ChatTimelineProjection` собирается swiftc'ом из
настоящего исходника, без симулятора. Сценарий из жизни (чат «Ты мне можешь…»,
30.10.2026): владелец спросил в 16:06, в 16:14 написал второй вопрос, и только
потом сервер дописал частичный ответ на первый — с признаком остановки.

Правило: ответ, закрытый остановкой, стоит там, где стоял его живой ход, —
сразу после своего вопроса. Иначе в ленте два вопроса подряд, а работа роли
ниже второго.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

MAIN = r'''
import Foundation

var failures: [String] = []

func expect(_ name: String, _ got: [String], _ want: [String]) {
    if got != want {
        failures.append(name + ": got " + got.joined(separator: ",") + " want " + want.joined(separator: ","))
    }
}

// 1. Сценарий владельца: два вопроса, ответ на первый закрыт остановкой.
let interrupted = ChatTimelineProjection.project(
    messages: [
        .init(id: "q1"),
        .init(id: "q2"),
        .init(id: "a1", anchorMessageID: "q1"),
    ],
    turns: [])
expect("interrupted answer stands after its question",
       interrupted.map(\.id), ["msg:q1", "msg:a1", "msg:q2"])

// 2. Обычный ответ (без остановки) остаётся в серверном порядке.
let normal = ChatTimelineProjection.project(
    messages: [.init(id: "q1"), .init(id: "a1"), .init(id: "q2")],
    turns: [])
expect("normal answer keeps server order", normal.map(\.id), ["msg:q1", "msg:a1", "msg:q2"])

// 3. Живой ход нового вопроса стоит после нового вопроса, а не выше ответа.
let withTurn = ChatTimelineProjection.project(
    messages: [.init(id: "q1"), .init(id: "q2"), .init(id: "a1", anchorMessageID: "q1")],
    turns: [.init(playbackID: "t2", anchorMessageID: "q2")])
expect("live turn of the new question stays after it",
       withTurn.map(\.id), ["msg:q1", "msg:a1", "msg:q2", "turn:t2"])

// 4. Два ответа на один вопрос сохраняют порядок между собой.
let twice = ChatTimelineProjection.project(
    messages: [
        .init(id: "q1"),
        .init(id: "q2"),
        .init(id: "a1", anchorMessageID: "q1"),
        .init(id: "a2", anchorMessageID: "q1"),
    ],
    turns: [])
expect("two answers on the same question keep their order",
       twice.map(\.id), ["msg:q1", "msg:a1", "msg:a2", "msg:q2"])

// 5. Вопроса в ленте нет (история не загружена) — сообщение не теряется и
//    не улетает в хвост, остаётся на своём месте.
let unknown = ChatTimelineProjection.project(
    messages: [.init(id: "a1", anchorMessageID: "gone"), .init(id: "q2")],
    turns: [])
expect("unknown anchor keeps the message in place",
       unknown.map(\.id), ["msg:a1", "msg:q2"])

// 6. Якорь на само себя не двигает строку.
let selfAnchor = ChatTimelineProjection.project(
    messages: [.init(id: "q1"), .init(id: "q2", anchorMessageID: "q2")], turns: [])
expect("self anchor does not move the row", selfAnchor.map(\.id), ["msg:q1", "msg:q2"])

// 7. Ход без якоря по-прежнему в хвосте, ответ на вопрос — у вопроса.
let tail = ChatTimelineProjection.project(
    messages: [.init(id: "q1"), .init(id: "q2"), .init(id: "a1", anchorMessageID: "q1")],
    turns: [.init(playbackID: "t1"), .init(playbackID: "t9", anchorMessageID: "missing")])
expect("turn without anchor goes to tail",
       tail.map(\.id), ["msg:q1", "msg:a1", "msg:q2", "turn:t1", "turn:t9"])

if failures.isEmpty {
    print("Chat interrupted-answer order: PASS (7)")
    exit(0)
}
for failure in failures { print("FAIL " + failure) }
exit(1)
'''

source = 'import Foundation\n' + (ROOT / 'Sources/Core/Models/ChatTimelineProjection.swift').read_text()
with tempfile.TemporaryDirectory(prefix='chat-interrupt-order-') as folder:
    main = Path(folder) / 'main.swift'
    main.write_text(source + MAIN)
    binary = Path(folder) / 'run'
    subprocess.run(['swiftc', str(main), '-o', str(binary)], check=True)
    if subprocess.run([str(binary)]).returncode != 0:
        raise SystemExit(1)


# --- Исходник экрана: передача хода от только что сменившегося к новому ------
#
# Экран не собирается без SwiftUI, поэтому здесь проверяется, что правила
# передачи записаны в коде, а не потеряны. Логика порядка ленты проверена выше
# настоящим прогоном модели.

SCREEN = (ROOT / 'Sources/Features/Chat/RoleChatsScreen.swift').read_text()


def block(text: str, marker: str) -> str:
    start = text.index(marker)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


failures: list[str] = []


def check(condition: bool, name: str) -> None:
    if not condition:
        failures.append(name)


show_live = block(SCREEN, 'private func showLiveTurn(')
check('parkLiveTurnIfUnanswered(previous' in show_live,
      'прежний ход остаётся в ленте, когда начинается новый')

park = block(SCREEN, 'private func parkLiveTurn(')
check('completingTurns[turn.playbackID]' in park and 'endedTurnIDs.insert' in park
      and 'stoppedTurnIDs.insert' in park,
      'сменившийся ход доигрывает как законченный и не выдаёт себя за отвеченный')

insert = block(SCREEN, 'private func insertIncoming(')
check('parkedTurn(answering: message, author: author)' in insert,
      'ответ прерванного хода занимает его строку, а не встаёт вторым')

refresh_block = block(SCREEN, 'private func refresh() async')
check('parkedTurn(answering: message, author: author)' in refresh_block,
      'снимок ленты тоже закрывает доигрывающий ход')

feed = block(SCREEN, 'private var feedItems: [FeedItem]')
check('anchorMessageID: feedAnchor(for:' in feed,
      'лента ставит ответ, закрытый остановкой, к своему вопросу')

anchor = block(SCREEN, 'private func feedAnchor(')
check('message.stopReason != nil' in anchor and 'message.replyToMessageID' in anchor,
      'правило якоря: только ответ с остановкой, к своему вопросу')

scrolling = block(SCREEN, 'private var messageScroll: some View')
check('.scrollPosition($chatScrollPosition)' in scrolling
      and '.scrollPosition($chatScrollPosition, anchor:' not in scrolling,
      'у привязки позиции один механизм, без второго якоря')
check('.defaultScrollAnchor(chatFollowsBottom ? .bottom : nil, for: .sizeChanges)' in scrolling,
      'низ держится, пока владелец сам не отлистал')
check('.animation(TFMotion.standard, value: orderedFeed' not in scrolling,
      'вставка строк ленты не анимируется')

turn_row = block(SCREEN, 'private func liveTurnRow(')
check('endedTurnIDs.contains(turn.playbackID)' in turn_row,
      'законченный ход показывается сразу, без повторного проявления')

if failures:
    for name in failures:
        print('FAIL ' + name)
    raise SystemExit(1)
print('Chat interruption handoff: PASS (' + str(9) + ')')
