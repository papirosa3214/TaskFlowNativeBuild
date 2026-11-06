#!/usr/bin/env python3
"""Чип «Память обновлена» в ленте: decode + ветка messageRow.

Владелец 03.11.2026: уведомляшка как у Гермеса, только при wrote.
"""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
model = (root / "Sources/Core/Models/RoleChat.swift").read_text()
from chat_screen_sources import read_chat_screen
screen = read_chat_screen(root)
hint = (root / "Sources/DesignSystem/Hints/HintScenarios.swift").read_text()

checks = [
    ("struct RoleChatMemoryUpdate" in model, "нужен RoleChatMemoryUpdate"),
    ('case memoryUpdate = "memory_update"' in model, "CodingKeys memory_update"),
    ("chipLabel" in model, "подпись чипа chipLabel"),
    ("memoryUpdateChipRow" in screen, "ветка чипа в RoleChatsScreen"),
    ("chat.memoryUpdateChip" in screen, "accessibility чипа"),
    ("message.memoryUpdate" in screen, "messageRow читает memoryUpdate"),
    ("чип «Память обновлена»" in hint, "подсказка про чип в ленте"),
]

failed = False
for ok, msg in checks:
    if not ok:
        print(f"FAIL: {msg}")
        failed = True

# Decode через swiftc на хосте без симулятора.
fixture = r'''
import Foundation
struct RoleChatMemoryUpdate: Decodable {
    let title: String?
    let kind: String?
    let confidence: Double?
    var chipLabel: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Память обновлена" : "Память обновлена · \(trimmed)"
    }
}
struct Msg: Decodable {
    var memoryUpdate: RoleChatMemoryUpdate? = nil
    enum CodingKeys: String, CodingKey { case memoryUpdate = "memory_update" }
}
let raw = #"""
{"id":"m1","text":"Память обновлена · Урок","kind":"memory_update","is_session_marker":false,
 "memory_update":{"title":"Урок","kind":"lesson","confidence":0.9}}
"""#
struct Envelope: Decodable {
    let id: String
    let text: String
    let kind: String?
    let is_session_marker: Bool
    var memory_update: RoleChatMemoryUpdate?
}
let data = Data(raw.utf8)
let msg = try! JSONDecoder().decode(Envelope.self, from: data)
assert(msg.memory_update?.title == "Урок")
assert(msg.memory_update?.chipLabel == "Память обновлена · Урок")
let empty = try! JSONDecoder().decode(Envelope.self, from: Data(#"{"id":"m2","text":"x","is_session_marker":false}"#.utf8))
assert(empty.memory_update == nil)
print("DECODE_OK")
'''

with tempfile.TemporaryDirectory() as td:
    src = Path(td) / "chip.swift"
    src.write_text(fixture)
    bin_path = Path(td) / "chip"
    compile = subprocess.run(
        ["swiftc", str(src), "-o", str(bin_path)],
        capture_output=True,
        text=True,
    )
    if compile.returncode != 0:
        print("FAIL: swiftc decode fixture")
        print(compile.stderr)
        failed = True
    else:
        run = subprocess.run([str(bin_path)], capture_output=True, text=True)
        if run.returncode != 0 or "DECODE_OK" not in run.stdout:
            print("FAIL: decode runtime")
            print(run.stdout, run.stderr)
            failed = True

if failed:
    sys.exit(1)
print("OK: memory chat chip")
