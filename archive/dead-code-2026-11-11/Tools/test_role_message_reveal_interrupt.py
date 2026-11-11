#!/usr/bin/env python3
"""Проявление готового сообщения: не оставлять половину фразы.

Владелец 03.11.2026: в чатах видна первая половина фразы, вторая нет.
Причина: Task проявления отменялся (`guard !Task.isCancelled`), fade с
isAnimating оставался, finished=true блокировал повторный старт.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
src = (root / "Sources/Features/Roles/RoleMessageReveal.swift").read_text()

checks = [
    ("enum RoleMessageRevealLifecycle" in src, "нужен RoleMessageRevealLifecycle"),
    ("fadeAfterInterrupt" in src, "нужен fadeAfterInterrupt"),
    ("fadeAfterRevealCompleted" in src, "нужен fadeAfterRevealCompleted"),
    ("snapIfStillAnimating" in src or "onDisappear" in src, "onDisappear снимает зависший fade"),
    ("guard !Task.isCancelled else { return }" not in src, "нельзя выходить из Task без снятия fade"),
    ("RoleMessageRevealLifecycle.fadeAfterRevealCompleted()" in src, "конец таймера через lifecycle"),
]

failed = False
for ok, msg in checks:
    if not ok:
        print(f"FAIL: {msg}")
        failed = True

# Вырезаем enum и гоняем на хосте.
marker = "enum RoleMessageRevealLifecycle {"
if marker not in src:
    print("FAIL: нет enum")
    sys.exit(1)
start = src.index(marker)
# до следующего top-level extension View
end = src.index("\nextension View {", start)
lifecycle = src[start:end]
# RoleTextFade живёт в RoleLiveTurnView — минимальная заглушка.
fixture = f'''
import Foundation

struct RoleTextFade: Equatable {{
    var rate: Double = 40
    var lastRevealAt: Date = .distantPast
    var isAnimating = false
    var revealsForward = false
}}

{lifecycle}

let animating = RoleTextFade(isAnimating: true, revealsForward: true)
assert(RoleMessageRevealLifecycle.fadeAfterInterrupt(current: animating) == nil)
assert(RoleMessageRevealLifecycle.fadeAfterInterrupt(current: RoleTextFade(isAnimating: false))?.isAnimating == false)
assert(RoleMessageRevealLifecycle.fadeAfterRevealCompleted() == nil)
assert(RoleMessageRevealLifecycle.resolvedFade(finished: true, current: animating, preferAnimate: true) == nil)
assert(RoleMessageRevealLifecycle.resolvedFade(finished: true, current: nil, preferAnimate: true) == nil)
let settled = RoleTextFade(isAnimating: false)
assert(RoleMessageRevealLifecycle.resolvedFade(finished: true, current: settled, preferAnimate: true)?.isAnimating == false)
print("OK")
'''

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "reveal.swift"
    path.write_text(fixture)
    binary = Path(td) / "reveal"
    compile = subprocess.run(["swiftc", str(path), "-o", str(binary)], capture_output=True, text=True)
    if compile.returncode != 0:
        print("FAIL: swiftc")
        print(compile.stderr)
        failed = True
    else:
        run = subprocess.run([str(binary)], capture_output=True, text=True)
        if run.returncode != 0 or "OK" not in run.stdout:
            print("FAIL: runtime")
            print(run.stdout, run.stderr)
            failed = True

if failed:
    sys.exit(1)
print("OK: role message reveal interrupt")
