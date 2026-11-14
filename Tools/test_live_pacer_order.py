#!/usr/bin/env python3
"""Идущий ответ роли: проза печатается ровным темпом, блоки — по порядку.

Владелец 06.11.2026: длинный ответ помощника «в секунду весь шлёпнулся»;
таблица в середине ответа должна вставиться целиком, когда до неё дошла
проза, а не раньше. Настоящий `RoleLiveTextPacer` из
`Sources/Core/Models/RoleChat.swift` прогоняется swiftc'ом на маке, без
симулятора.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODEL = (ROOT / 'Sources/Core/Models/RoleChat.swift').read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


STUBS = r'''
import Foundation
enum RoleChatLiveItem: Equatable {
    case text(String), step(String), thinking(String)
    var actionID: String? {
        switch self {
        case .text: return nil
        case .step(let id): return "step:" + id
        case .thinking(let id): return "thinking:" + id
        }
    }
}
struct ChatLiveBlock { let source: String; let isProse: Bool }
final class ChatLiveBlockRegistry {
    static let shared = ChatLiveBlockRegistry()
    var map: [String: [ChatLiveBlock]] = [:]
    // Копия живого API: область (сессия + ход) есть, поведение — по тексту.
    func blocks(for text: String, scope: String? = nil) -> [ChatLiveBlock]? { map[text] }
}
enum ChatRichContent {
    static let htmlLanguages: Set<String> = ["html"]
    static let widgetLanguages: Set<String> = ["widget"]
}
'''

MAIN = r'''
var failures: [String] = []
func check(_ name: String, _ ok: Bool) { if !ok { failures.append(name) } }

let prose1 = String(repeating: "слово ", count: 200)   // 1200 знаков
let table = "| a | b |\n|---|---|\n| 1 | 2 |\n"
let prose2 = String(repeating: "хвост ", count: 100)
let whole = prose1 + table + prose2
ChatLiveBlockRegistry.shared.map[whole] = [
    ChatLiveBlock(source: prose1, isProse: true),
    ChatLiveBlock(source: table, isProse: false),
    ChatLiveBlock(source: prose2, isProse: true),
]

func shownText(_ p: RoleLiveTextPacer) -> String {
    p.visibleItems.map { if case .text(let t) = $0 { return t } else { return "" } }.joined()
}

// 1. Таблица не видна, пока проза перед ней не допечатана.
var pacer = RoleLiveTextPacer()
pacer.ingest([.text(whole)])
let t0 = Date()
var clock = 0.0
func step(_ s: Double) { clock += s; pacer.advance(elapsed: s, now: t0.addingTimeInterval(clock)) }
for _ in 0..<10 { step(0.1) }
let early = shownText(pacer)
check("table hidden while prose before it is typing", !early.contains("| a |"))
check("some prose already shown", early.count > 0)

// 2. Скорость прозы — не выше потолка, даже когда очередь большая.
check("rate within prose cap", pacer.rate <= RoleLiveTextPacer.maxProseRate + 0.001)
check("one second shows at most ~cap chars", early.count <= Int(RoleLiveTextPacer.maxProseRate * 1.0) + 12)

// 3. Ответ готов: остаток не сбрасывается за доли секунды.
pacer.finish()
for _ in 0..<10 { step(0.1) }
let afterFinish = shownText(pacer)
check("finish does not dump the rest within a second", afterFinish.count < whole.count)

// 4. Когда проза дошла до таблицы — таблица целиком, потом второй абзац.
for _ in 0..<400 { step(0.1); if shownText(pacer) == whole { break } }
check("everything shown in the end", shownText(pacer) == whole)

// 5. Таблица появляется целиком, ровно после первого абзаца.
var p2 = RoleLiveTextPacer()
p2.ingest([.text(whole)])
var seenTablePartial = false
var tableBeforeProse = false
var c2 = 0.0
for _ in 0..<600 {
    c2 += 0.05
    p2.advance(elapsed: 0.05, now: t0.addingTimeInterval(c2))
    let s = p2.visibleItems.map { if case .text(let t) = $0 { return t } else { return "" } }
    let joined = s.joined()
    if joined.contains("| a |") {
        if !joined.contains(table) { seenTablePartial = true }
        if !joined.hasPrefix(prose1) { tableBeforeProse = true }
    }
    if joined == whole { break }
}
check("table never partial", !seenTablePartial)
check("table only after first paragraph", !tableBeforeProse)

if failures.isEmpty { print("Live pacer order and pace: PASS"); exit(0) }
for f in failures { print("FAIL " + f) }
exit(1)
'''

production = '\n'.join([
    block(MODEL, 'enum RoleLiveTurnGrowth'),
    block(MODEL, 'struct RoleLiveTextPacer {'),
])
with tempfile.TemporaryDirectory(prefix='live-pacer-') as tmp:
    main = Path(tmp) / 'main.swift'
    main.write_text(STUBS + production + '\n' + MAIN)
    binary = Path(tmp) / 'run'
    build = subprocess.run(['swiftc', str(main), '-o', str(binary)], capture_output=True, text=True)
    if build.returncode:
        print('\n'.join(l for l in build.stderr.splitlines() if 'error:' in l)[:3000])
        raise SystemExit(1)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
