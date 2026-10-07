#!/usr/bin/env python3
"""Гейт «одинаковые компоненты» (владелец 07.10.2026).

Правило владельца: если элемент уже есть в приложении, он должен выглядеть
везде одинаково; рисуешь иначе — остановись. Прецедент: «На проверке» в
списках была синей, а в шапке карточки её нарисовали зелёной.

PreToolUse на Edit|Write. Смотрит правку Swift-файла в Sources/: если в ней
рисуется подпись, которая уже напечатана в другом файле, или в Features
заводится новый View, — один раз блокирует правку и показывает, где это уже
нарисовано. Повтор той же правки проходит: гейт заставляет сверить, а не
запрещает.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

STATE_DIR = "/tmp/claude-same-component-gate"
PASS_TTL = 6 * 3600
DRAWING = re.compile(r"\b(Text|Image|Label|Button)\(|\.foregroundStyle\(|\.font\(|\.tfText\(")
LITERAL = re.compile(r'"((?:[^"\\\n]|\\[^(])*)"')
NEW_VIEW = re.compile(r"\bstruct\s+(\w+)\s*:\s*(?:[\w.]+\s*,\s*)*View\b")


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
    text = tool_input.get("new_string") or tool_input.get("content") or ""
    if not DRAWING.search(text):
        return 0

    rel = os.path.relpath(os.path.abspath(path), root)
    findings = []
    # Подписи кириллицей — то, что видит владелец; ищем без учёта регистра.
    labels = []
    for literal in LITERAL.findall(text):
        literal = literal.strip()
        if len(literal) >= 4 and re.search(r"[А-Яа-яЁё]", literal) and literal not in labels:
            labels.append(literal)
    for label in labels[:8]:
        hits = grep(root, label, exclude=rel)
        if hits:
            findings.append((f"подпись «{label}»", hits))
    if os.sep + "Features" + os.sep in os.path.abspath(path):
        for name in NEW_VIEW.findall(text):
            if not grep(root, f"struct {name}", exclude=None):
                components = sorted(os.listdir(os.path.join(sources, "DesignSystem", "Components")))
                findings.append((f"новый View `{name}` в Features",
                                 ["готовые компоненты: " + ", ".join(c.removesuffix(".swift") for c in components)]))
    if not findings:
        return 0

    key = hashlib.sha1((rel + "|" + "|".join(sorted(f[0] for f in findings))).encode()).hexdigest()
    os.makedirs(STATE_DIR, exist_ok=True)
    marker = os.path.join(STATE_DIR, key)
    if os.path.exists(marker) and time.time() - os.path.getmtime(marker) < PASS_TTL:
        return 0
    open(marker, "w").close()

    lines = ["ГЕЙТ «одинаковые компоненты» (владелец 07.10.2026): это в приложении уже нарисовано."]
    for title, hits in findings:
        lines.append(f"• {title}:")
        lines.extend(f"    {hit}" for hit in hits)
    lines += [
        "Сверь с этими местами цвет, шрифт, регистр, значок и условия показа — должно быть одинаково.",
        "Есть общий компонент или функция — используй их. Нет — вынеси общий в Sources/DesignSystem и подключи во всех местах.",
        "Тот же элемент может быть и в вебе (.110: ~/Проекты/New-Todoist/src) — сверь и с ним.",
        "Отличие намеренное — сначала скажи владельцу. Сверил — повтори правку, второй раз гейт её пропустит.",
    ]
    print("\n".join(lines), file=sys.stderr)
    return 2


def grep(root: str, needle: str, exclude: str | None) -> list[str]:
    cmd = ["rg", "-n", "-i", "-F", "--no-heading", "-g", "*.swift", needle, "Sources"]
    try:
        out = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=8).stdout
    except Exception:
        return []
    hits = []
    for line in out.splitlines():
        file, _, rest = line.partition(":")
        if exclude and file == exclude:
            continue
        number, _, code = rest.partition(":")
        if code.strip().startswith("//"):
            continue
        hits.append(f"{file}:{number}: {code.strip()[:110]}")
    extra = len(hits) - 4
    return hits[:4] + ([f"… и ещё {extra}"] if extra > 0 else [])


if __name__ == "__main__":
    sys.exit(main())
