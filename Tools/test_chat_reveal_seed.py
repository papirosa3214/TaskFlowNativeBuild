#!/usr/bin/env python3
"""Семя проявления: короткий кэш не должен заново проявлять историю."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
src = (root / "Sources/Core/Models/RoleChat.swift").read_text()
screen = (root / "Sources/Features/Roles/RoleChatsScreen.swift").read_text()

marker = "enum RoleChatRevealSeed"
if marker not in src:
    print("FAIL: нет RoleChatRevealSeed"); sys.exit(1)
checks = [
    ("RoleChatRevealSeed.settle" in screen, "экран не зовёт settle"),
    ("RoleChatRevealSeed.shouldReveal" in screen, "экран не зовёт shouldReveal"),
    ("historySeedSettled" in screen, "нет historySeedSettled"),
    ("shouldRevealMessage(message)" in screen, "animate не через shouldRevealMessage"),
    ("chatIsNearBottom && message.id == messages.last" not in screen, "старый animate без семени остался"),
]
failed = False
for ok, msg in checks:
    if not ok:
        print("FAIL:", msg); failed = True

start = src.index(marker)
opening = src.index("{", start)
depth, end = 1, opening + 1
while depth:
    depth += (src[end] == "{") - (src[end] == "}")
    end += 1
helper = src[start:end]

fixture = """
import Foundation
""" + helper + r"""

func check(_ name: String, _ ok: Bool) {
    if !ok { fputs("FAIL: \(name)\n", stderr); exit(1) }
}

let first = RoleChatRevealSeed.settle(current: ["a"], snapshotIDs: ["a", "b", "c"], settled: false)
check("settle unions", first.seed == Set(["a", "b", "c"]) && first.settled)
check("before settle silent",
      RoleChatRevealSeed.shouldReveal(
        messageID: "c", seed: ["a"], settled: false, isLast: true,
        nearBottom: true, closedTurnMessageIDs: []) == false)
check("history after settle silent",
      RoleChatRevealSeed.shouldReveal(
        messageID: "c", seed: first.seed, settled: true, isLast: true,
        nearBottom: true, closedTurnMessageIDs: []) == false)
check("new after settle reveals",
      RoleChatRevealSeed.shouldReveal(
        messageID: "d", seed: first.seed, settled: true, isLast: true,
        nearBottom: true, closedTurnMessageIDs: []) == true)
check("empty unsettled silent",
      RoleChatRevealSeed.shouldReveal(
        messageID: "x", seed: [], settled: false, isLast: true,
        nearBottom: true, closedTurnMessageIDs: []) == false)
print("PASS: RoleChatRevealSeed")
"""

with tempfile.TemporaryDirectory(prefix="reveal-seed-") as tmp:
    path = Path(tmp)
    (path / "main.swift").write_text(fixture)
    build = subprocess.run(["swiftc", str(path / "main.swift"), "-o", str(path / "run")],
                           capture_output=True, text=True)
    if build.returncode != 0:
        print("FAIL: стенд не собрался"); print(build.stderr); sys.exit(1)
    run = subprocess.run([str(path / "run")], capture_output=True, text=True)
    print(run.stdout, end="")
    if run.returncode != 0:
        print(run.stderr, end=""); failed = True
if failed: sys.exit(1)
print("PASS: семя проявления при открытии чата")
