#!/usr/bin/env python3
"""Сторож правил сборки iOS (владелец 12–13.11.2026: «не убивать мой ноутбук»).

Правила — CLAUDE.md, раздел «Сборка iOS — не перегревать мак». Хук держит их
сам, до запуска:

- `xcodebuild` без `-jobs 2`, с `clean`, при уже идущей сборке/тестах —
  отклоняется;
- удаление DerivedData и каталогов сборки — отклоняется;
- сборка `xcodebuild` по правилам, установка на iPhone через службу
  установщика, сборки/предпросмотры/запуски/тесты Xcode MCP — только с
  подтверждения владельца (окно разрешения), каждый раз отдельно. Xcode MCP
  не даёт задать `-jobs`, поэтому в окне это сказано прямо.
"""
import json
import re
import subprocess
import sys

data = json.load(sys.stdin)
tool = data.get("tool_name", "")
inp = data.get("tool_input", {}) or {}


def decide(kind: str, reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": kind,
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def busy() -> str:
    out = subprocess.run(["pgrep", "-fl", "xcodebuild|xctest|XCTRunner"],
                         capture_output=True, text=True).stdout
    lines = [l for l in out.splitlines() if "xcodebuildmcp" not in l]
    return "\n".join(lines)


HEAVY_MCP = re.compile(
    r"^mcp__(xcode__(BuildProject|RunProject|RenderPreview|RunAllTests|RunSomeTests)"
    r"|XcodeBuildMCP__(build|test|build_run|clean|boot_sim|launch_app|install_app)\w*)$"
)

if HEAVY_MCP.match(tool):
    if busy():
        decide("deny", "Правило сборки 1/6: уже идёт сборка или тесты — вторую не запускать.")
    decide("ask", "Тяжёлое действие Xcode MCP: оно не ограничивает параллелизм (-jobs 2 задать нельзя). "
                  "Запускать только по прямому «да» владельца на это действие.")

if tool == "Bash":
    cmd = inp.get("command", "")
    if re.search(r"rm\s+-[a-zA-Z]*r[a-zA-Z]*\s+[^;&|]*(DerivedData|build_device|build_sim|build_generic)", cmd):
        decide("deny", "Правило сборки 2: удалять DerivedData и каталоги сборки — только с отдельного разрешения владельца.")
    if re.search(r"(?<![\w-])xcodebuild(?![\w-])", cmd):
        if re.search(r"(?<![\w-])clean(?![\w-])", cmd):
            decide("deny", "Правило сборки 2: clean build — только с отдельного разрешения владельца.")
        if re.search(r"(?<![\w-])(build|test|archive|build-for-testing)(?![\w-])", cmd):
            if not re.search(r"-jobs\s+2(?!\d)", cmd):
                decide("deny", "Правило сборки 4: xcodebuild только с -jobs 2.")
            if busy():
                decide("deny", "Правило сборки 1/6: уже идёт сборка или тесты — дождаться окончания.")
            decide("ask", "Сборка xcodebuild (-jobs 2). Запускать только по прямому «да» владельца.")
    if "8791/install" in cmd or "install-iphone.sh" in cmd:
        if busy():
            decide("deny", "Правило сборки 1/6: уже идёт сборка или тесты — установку не начинать.")
        decide("ask", "Установка на iPhone — это сборка Release. Только по прямому «да» владельца.")

sys.exit(0)
