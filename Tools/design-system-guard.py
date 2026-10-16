#!/usr/bin/env python3
"""Сторож дизайн-системы TaskFlow.

Зачем (владелец 16.10.2026): модели пишут UI мимо `Sources/DesignSystem/` —
голый системный `Toggle` (крупнее и зелёный вместо `TFToggle`), системные
цвета текста, сырой кегль на `Text`, самодельные кнопки. Сторож ловит это в
момент правки и говорит, чем заменить: «не соответствует — надо так».

Один источник правил для всех: этот скрипт. Его зовут три входа:
  • шаг сборки (`project.yml`, `preBuildScripts`) — `--diff HEAD`, падает у
    любой модели, независимо от инструмента;
  • хук Claude Code (`.claude/hooks/guard_design_system.py`) — режимы
    `--fragment` / `--new-file`, блокирует правку до записи;
  • вручную — `python3 Tools/design-system-guard.py` (отчёт по всему коду).

Режимы:
  (без флагов)        отчёт по всему `Sources/`
  --paths F [F ...]   только перечисленные файлы
  --diff [REV]        только строки, добавленные относительно REV (по умолчанию
                      HEAD) в `Sources/`, плюс целиком новые (untracked) файлы
  --fragment          текст правки со stdin — как отдельный фрагмент (Edit)
  --new-file PATH     новое содержимое файла PATH со stdin; проверяются только
                      добавленные строки относительно того, что лежит на диске

Код возврата: 1, если есть ошибки (error); 0 при чистом результате и при
одних предупреждениях (warn).

Осознанный отказ от правила — строка `// design-system-guard: ignore`
в самой строке нарушения.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

IGNORE_MARK = "design-system-guard: ignore"

# Пары «что ищем — чем заменить». Правило error роняет сборку, warn только
# сообщает.
RULES = [
    {
        "id": "raw-toggle",
        "severity": "error",
        "title": "голый системный `Toggle`",
        "fix": "используй `TFToggle(isOn:)` — единственный тумблер приложения "
               "(меньше и красный): HStack { Text(\"…\"); Spacer(); TFToggle(isOn: $x) }",
    },
    {
        "id": "system-text-color",
        "severity": "error",
        "title": "системный цвет текста (`.primary`/`.secondary`/`.tertiary`)",
        "fix": "цвет из палитры: `tfText` (основной) / `tfSub` (вторичный) / `tfDim` (третичный)",
    },
    {
        "id": "text-font-size",
        "severity": "error",
        "title": "сырой кегль `.font(.system(size:))` на `Text`",
        "fix": "ступень шкалы через `.tfText(.body/.action/.meta/…)` — все размеры живут "
               "в `Sources/DesignSystem/Theme/Typography.swift`",
    },
    {
        "id": "bespoke-button",
        "severity": "warn",
        "title": "похоже на самодельную кнопку со своей рамкой/фоном",
        "fix": "готовые кнопки: `TFButton` (полноширинная, варианты primary/secondary/outline), "
               "`TFIconButton` (иконка, тап-зона 44×44)",
    },
]

TOGGLE = re.compile(r"(?<![\w.])Toggle\s*\(")
SYSTEM_COLOR = re.compile(r"\.foreground(Style|Color)\(\.(primary|secondary|tertiary)\b")
TEXT_FONT = re.compile(r"\.font\(\.system\(size:")
TEXT_CTOR = re.compile(r"\bText\s*\(")
BUTTON = re.compile(r"(?<![\w.])Button\s*[\({]")
# Своя главная кнопка: заливка красным вручную вместо `TFButton`.
BESPOKE_FILL = re.compile(r"\.background\((?:Color\.)?tfRed(Solid)?\b")


def strip_comment(line: str) -> str:
    """Убирает `//…` вне строковых литералов."""
    out = []
    in_string = False
    escaped = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
                out.append(ch)
            elif ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
            else:
                out.append(ch)
        i += 1
    return "".join(out)


def statement_head(lines, index: int) -> str:
    """Строка-«голова» выражения, к которому относится модификатор на index.

    Идём вверх, пока строки начинаются с `.` (цепочка модификаторов); первая
    строка, не начинающаяся с `.`, — начало выражения.
    """
    j = index
    while j >= 0:
        if not lines[j].strip().startswith("."):
            return lines[j]
        j -= 1
    return lines[index] if 0 <= index < len(lines) else ""


def check_line(path: str, lines, index: int):
    """Возвращает список сработавших правил для строки (index — 0-based)."""
    raw = lines[index]
    if IGNORE_MARK in raw:
        return []
    code = strip_comment(raw)
    hits = []
    if not path.endswith("Components/TFToggle.swift") and TOGGLE.search(code):
        hits.append("raw-toggle")
    if SYSTEM_COLOR.search(code):
        hits.append("system-text-color")
    if TEXT_FONT.search(code) and TEXT_CTOR.search(strip_comment(statement_head(lines, index))):
        hits.append("text-font-size")
    if BUTTON.search(code):
        window = "\n".join(strip_comment(x) for x in lines[max(0, index - 2): index + 8])
        if BESPOKE_FILL.search(window):
            hits.append("bespoke-button")
    return hits


def scan_file(path: str, only_lines=None):
    """Собирает находки в файле. only_lines — множество номеров (1-based)."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return []
    findings = []
    for index in range(len(lines)):
        if only_lines is not None and (index + 1) not in only_lines:
            continue
        for rule_id in check_line(path, lines, index):
            findings.append((path, index + 1, rule_id))
    return findings


def scan_fragment(text: str):
    lines = text.splitlines()
    findings = []
    for index in range(len(lines)):
        for rule_id in check_line("<правка>", lines, index):
            findings.append(("<правка>", index + 1, rule_id))
    return findings


def walk_sources(root: str):
    for dirpath, _dirs, files in os.walk(os.path.join(root, "Sources")):
        for name in files:
            if name.endswith(".swift"):
                yield os.path.join(dirpath, name)


def diff_added_lines(root: str, rev: str):
    """{абсолютный путь: множество добавленных строк} + список новых файлов."""
    try:
        out = subprocess.run(
            ["git", "-C", root, "diff", "--unified=0", "--no-color", rev, "--", "Sources"],
            capture_output=True, text=True, timeout=30,
        ).stdout
    except Exception:
        out = ""
    added = {}
    current = None
    newno = None
    for line in out.splitlines():
        if line.startswith("+++ "):
            target = line[4:].strip()
            if target == "/dev/null":
                current = None
                continue
            if target.startswith("b/"):
                target = target[2:]
            current = os.path.join(root, target)
            continue
        if line.startswith("@@"):
            match = re.match(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", line)
            newno = int(match.group(1)) if match else None
            continue
        if current is None or newno is None:
            continue
        if line.startswith("+"):
            added.setdefault(current, set()).add(newno)
            newno += 1
        elif line.startswith("-"):
            continue
        elif line.startswith(" "):
            newno += 1
    untracked = []
    try:
        listing = subprocess.run(
            ["git", "-C", root, "ls-files", "--others", "--exclude-standard", "--", "Sources"],
            capture_output=True, text=True, timeout=30,
        ).stdout
        untracked = [os.path.join(root, p) for p in listing.splitlines() if p.strip()]
    except Exception:
        untracked = []
    return added, untracked


def render(findings):
    by_rule = {rule["id"]: rule for rule in RULES}
    errors = [f for f in findings if by_rule[f[2]]["severity"] == "error"]
    warns = [f for f in findings if by_rule[f[2]]["severity"] == "warn"]
    if not findings:
        print("Сторож дизайн-системы: чисто.")
        return 0
    order = {"error": 0, "warn": 1}
    findings = sorted(findings, key=lambda f: (order[by_rule[f[2]]["severity"]], f[0], f[1]))
    print("Сторож дизайн-системы TaskFlow: НЕ СООТВЕТСТВУЕТ.")
    for path, line, rule_id in findings:
        rule = by_rule[rule_id]
        marker = "ОШИБКА" if rule["severity"] == "error" else "внимание"
        shown = path
        if os.path.isabs(path):
            try:
                shown = os.path.relpath(path)
            except ValueError:
                shown = path
        print("  [%s] %s:%d — %s" % (marker, shown, line, rule["title"]))
        print("      надо: %s" % rule["fix"])
    print("")
    print("Осознанное отклонение от правила — добавь в строку «// %s»." % IGNORE_MARK)
    if errors:
        print("Ошибок: %d. Сборка с правкой не пройдёт." % len(errors))
    if warns:
        print("Предупреждений: %d (сборку не роняют)." % len(warns))
    return 1 if errors else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Сторож дизайн-системы TaskFlow")
    parser.add_argument("--root", default=os.environ.get("SRCROOT") or os.getcwd())
    parser.add_argument("--paths", nargs="*")
    parser.add_argument("--diff", nargs="?", const="HEAD", default=None)
    parser.add_argument("--fragment", action="store_true")
    parser.add_argument("--new-file", default=None)
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    if args.fragment:
        return render(scan_fragment(sys.stdin.read()))

    if args.new_file:
        new_text = sys.stdin.read()
        existing = args.new_file if os.path.isabs(args.new_file) else os.path.join(root, args.new_file)
        try:
            with open(existing, "r", encoding="utf-8", errors="replace") as handle:
                old_lines = {line.strip() for line in handle.read().splitlines()}
        except OSError:
            old_lines = set()
        new_lines = new_text.splitlines()
        findings = []
        for index in range(len(new_lines)):
            # Строка, уже лежавшая в файле дословно, — старое соответствие,
            # его не приписываем этой правке.
            if new_lines[index].strip() in old_lines and new_lines[index].strip():
                continue
            for rule_id in check_line(existing, new_lines, index):
                findings.append((args.new_file, index + 1, rule_id))
        return render(findings)

    if args.diff is not None:
        added, untracked = diff_added_lines(root, args.diff)
        findings = []
        for path, lineset in added.items():
            findings.extend(scan_file(path, only_lines=lineset))
        for path in untracked:
            findings.extend(scan_file(path))
        return render(findings)

    if args.paths:
        findings = []
        for path in args.paths:
            full = path if os.path.isabs(path) else os.path.join(root, path)
            findings.extend(scan_file(full))
        return render(findings)

    findings = []
    for path in sorted(walk_sources(root)):
        findings.extend(scan_file(path))
    return render(findings)


if __name__ == "__main__":
    sys.exit(main())
