#!/usr/bin/env python3
"""Гейт «дизайн-система» (владелец 16.10.2026).

Правило владельца: модели не должны рисовать UI мимо `Sources/DesignSystem/`.
Прецедент: экран «Оценщик JEV» — голый системный `Toggle` вместо `TFToggle`
(крупнее и зелёный вместо маленького красного).

PreToolUse на Edit|Write. Смотрит правку Swift-файла в `Sources/`: зовёт
общий разбор `Tools/design-system-guard.py` (тот же, что стоит шагом сборки),
и если правка тумблера/типографики/кнопки не по системе — один раз блокирует
её и говорит, чем заменить. Повтор той же правки проходит: гейт заставляет
сверить, а не запрещает навсегда.

Тот же сторож работает и без Claude Code: любой агент может позвать
`python3 Tools/design-system-guard.py`, а `--diff HEAD` включён шагом сборки
(`project.yml`).
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

STATE_DIR = "/tmp/claude-design-system-gate"
PASS_TTL = 6 * 3600


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    tool_input = payload.get("tool_input") or {}
    path = tool_input.get("file_path") or ""
    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    sources = os.path.join(root, "Sources")
    if not path.endswith(".swift") or not os.path.abspath(path).startswith(sources + os.sep):
        return 0
    guard = os.path.join(root, "Tools", "design-system-guard.py")
    if not os.path.exists(guard):
        return 0

    if payload.get("tool_name") == "Write" or "content" in tool_input:
        text = tool_input.get("content") or ""
        argv = [sys.executable, guard, "--root", root, "--new-file", path]
    else:
        text = tool_input.get("new_string") or ""
        argv = [sys.executable, guard, "--root", root, "--fragment"]
    if not text.strip():
        return 0
    try:
        proc = subprocess.run(argv, input=text, capture_output=True, text=True,
                              cwd=root, timeout=20)
    except Exception:
        return 0
    if proc.returncode == 0:
        return 0
    report = (proc.stdout or "").strip() or (proc.stderr or "").strip()
    if not report:
        return 0

    rel = os.path.relpath(os.path.abspath(path), root)
    stable = re.sub(r":\d+", "", report)
    key = hashlib.sha1((rel + "|" + stable).encode()).hexdigest()
    os.makedirs(STATE_DIR, exist_ok=True)
    marker = os.path.join(STATE_DIR, key)
    if os.path.exists(marker) and time.time() - os.path.getmtime(marker) < PASS_TTL:
        return 0
    open(marker, "w").close()

    print(f"ГЕЙТ «дизайн-система» (владелец 16.10.2026): правка «{rel}» не по нашей системе.",
          file=sys.stderr)
    print(report, file=sys.stderr)
    print("Сверь с готовым компонентом и повтори правку — второй раз гейт её пропустит. "
          "Отклонение осознанное — добавь в строку «// design-system-guard: ignore».",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
