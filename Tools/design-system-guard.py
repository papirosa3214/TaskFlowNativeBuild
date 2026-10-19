#!/usr/bin/env python3
"""Сторож дизайн-системы TaskFlow.

Зачем (владелец 16.10.2026): модели пишут UI мимо `Sources/DesignSystem/` —
голый системный `Toggle` (крупнее и зелёный вместо `TFToggle`), системные
цвета текста, сырой кегль на `Text`, самодельные кнопки. Сторож ловит это в
момент правки и говорит, чем заменить: «не соответствует — надо так».

Один источник правил для всех: этот скрипт. Его зовут три входа:
  • шаг сборки (`project.yml`, `preBuildScripts`) — `--folder`, сканирует
    локальную папку `Sources/` целиком, а НЕ `git diff`: в рабочем цикле
    правка коммитится до сборки, diff пустой, и гейт молчал бы;
  • хук Claude Code (`.claude/hooks/guard_design_system.py`) — режимы
    `--fragment` / `--new-file`, блокирует правку до записи;
  • вручную — `python3 Tools/design-system-guard.py` (отчёт по всему коду).

Базовый снимок `Tools/design-system-baseline.txt` — нарушения, которые были
в коде на момент включения. Их гейт не роняет сборку (иначе проект стал бы
несобираемым до конца чистки), но печатает ВСЕГДА: это список работы. Роняет
только новое. Снимок должен только уменьшаться: починил нарушение — убирай
его строку.

Режимы:
  (без флагов)        отчёт по всему `Sources/`
  --paths F [F ...]   только перечисленные файлы
  --folder            вся локальная папка `Sources/` (то, что зовёт сборка)
  --diff [REV]        только строки, добавленные относительно REV (по умолчанию
                      HEAD) в `Sources/`, плюс целиком новые (untracked) файлы
  --baseline [PATH]   файл базового снимка (по умолчанию
                      `Tools/design-system-baseline.txt`)
  --fragment          текст правки со stdin — как отдельный фрагмент (Edit)
  --new-file PATH     новое содержимое файла PATH со stdin; проверяются только
                      добавленные строки относительно того, что лежит на диске

Код возврата: 1, если есть НОВЫЕ ошибки (error); 0 при чистом результате и при
одних предупреждениях (warn). Нарушения из базового снимка код возврата не
роняют — они в счётчике «уже было».

Осознанный отказ от правила — строка `// design-system-guard: ignore`
в самой строке нарушения.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import importlib.util
from pathlib import Path

_heading_spec = importlib.util.spec_from_file_location("screen_heading_guard", Path(__file__).with_name("screen-heading-guard.py"))
_heading_module = importlib.util.module_from_spec(_heading_spec)
_heading_spec.loader.exec_module(_heading_module)
scan_screen_headings = _heading_module.scan_screen_headings

IGNORE_MARK = "design-system-guard: ignore"

# Шапка файла базового снимка (Tools/design-system-baseline.txt).
BASELINE_HEADER = """# Базовый снимок сторожа дизайн-системы: нарушения, которые уже были в коде
# на момент его включения (16.10.2026). Сборку они НЕ роняют — иначе проект
# стал бы несобираемым до конца чистки, — но печатаются всегда как список работы.
#
# Формат: путь<TAB>правило<TAB>строка кода (табуляция обязательна).
# Номер строки не хранится намеренно: он сдвигается от чужой правки выше по
# файлу, и снимок по номерам ложно объявил бы старое нарушение новым.
#
# Починил нарушение — УБЕРИ его строку отсюда. Снимок должен только уменьшаться.
# Перегенерировать (только осознанно, для новых правил):
#   python3 Tools/design-system-guard.py --write-baseline
"""

# Пары «что ищем — чем заменить». Правило error роняет сборку, warn только
# сообщает.
RULES = [
    {
        "id": "screen-heading-consistency",
        "severity": "error",
        "title": "разный стиль заголовков одного уровня внутри экрана",
        "fix": "сверь соседние разделы указанного экрана: используй общий компонент без переопределения шрифта, цвета и регистра; детали в Tools/screen-heading-scopes.json",
    },
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
    # Ниже — правила из свода критериев аудита дизайн-системы
    # (`docs/2026-10-16-design-system-audit/external-references.md`, группы A–G):
    # внешние ориентиры Apple HIG и WCAG, сведённые в проверяемые утверждения.
    {
        "id": "text-too-small",
        "severity": "error",
        "title": "кегль меньше 11 pt — ниже минимума iOS (B2)",
        "fix": "минимум 11 pt: ступень `.tfText(.caption)`. Если это глиф (`Image`), "
               "а не текст, правило не применяется",
    },
    {
        "id": "light-font-weight",
        "severity": "error",
        "title": "светлое начертание (`.ultraLight`/`.thin`) — HIG не рекомендует (B4)",
        "fix": "обычное или полужирное начертание: `.regular` / `.medium` / `.semibold`",
    },
    {
        "id": "alert-ok-button",
        "severity": "error",
        "title": "кнопка диалога «OK»/«ОК» — не называет результат (C4.3)",
        "fix": "назови результатом или глаголом: «Повторить», «Удалить», «Закрыть», «Понятно»",
    },
    {
        "id": "alert-generic-title",
        "severity": "error",
        "title": "заголовок диалога «Ошибка»/«Error» — не описывает ситуацию (C4.2)",
        "fix": "опиши ситуацию словами экрана: «Не удалось сохранить задачу», «Нет связи с сервером»",
    },
    {
        "id": "custom-font",
        "severity": "warn",
        "title": "свой шрифт вне `DesignSystem/` (B1)",
        "fix": "шрифт берётся из шкалы `Sources/DesignSystem/Theme/Typography.swift`, "
               "а не задаётся на экране",
    },
]

TOGGLE = re.compile(r"(?<![\w.])Toggle\s*\(")
SYSTEM_COLOR = re.compile(r"\.foreground(Style|Color)\(\.(primary|secondary|tertiary)\b")
TEXT_FONT = re.compile(r"\.font\(\.system\(size:")
TEXT_CTOR = re.compile(r"\bText\s*\(")
IMAGE_CTOR = re.compile(r"\bImage\s*\(")
BUTTON = re.compile(r"(?<![\w.])Button\s*[\\({]")
# Своя главная кнопка: заливка красным вручную вместо `TFButton`.
BESPOKE_FILL = re.compile(r"\.background\((?:Color\.)?tfRed(Solid)?\b")

# --- Критерии аудита (external-references.md, группы A–G) ---
# B2: кегль меньше 11 pt. Число ловим из вызова, сравниваем в check_line.
FONT_SIZE = re.compile(r"\.font\(\.system\(size:\s*([0-9]+(?:\.[0-9]+)?)")
# B4: светлые начертания. `.light` нарочно НЕ в списке — слишком много
# одноимённых совпадений (`thinMaterial`, `lightning`, `.highlight`).
LIGHT_WEIGHT = re.compile(r"\.fontWeight\(\s*\.(?:ultraLight|thin)\b|\.weight\(\s*\.(?:ultraLight|thin)\b")
# C4.3: кнопка диалога, не называющая результат.
VAGUE_BUTTON = re.compile(r"(?<![\w.])Button\s*\(\s*\"(?:OK|Ok|ok|ОК|Ок|ок)\"")
# C4.2: заголовок диалога без описания ситуации.
GENERIC_ALERT = re.compile(r"\.alert\s*\(\s*\"(?:Ошибка|ОШИБКА|Ошибка!|Error|ERROR|Ошибка:)\"")
# B1: свой шрифт. В `DesignSystem/` он законен (шкала и компоненты), вне — нет.
CUSTOM_FONT = re.compile(r"\.font\(\s*\.custom\(|Font\.custom\(")
MIN_TEXT_SIZE = 11.0


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
    head = strip_comment(statement_head(lines, index))
    # B2 важнее общего «сырой кегль»: если размер ниже минимума, называем
    # именно это — иначе на одной строке сыпались бы два правила.
    size_match = FONT_SIZE.search(code)
    too_small = (size_match is not None
                 and float(size_match.group(1)) < MIN_TEXT_SIZE
                 and TEXT_CTOR.search(head)
                 and not IMAGE_CTOR.search(head))
    if too_small:
        hits.append("text-too-small")
    elif TEXT_FONT.search(code) and TEXT_CTOR.search(head):
        hits.append("text-font-size")
    if LIGHT_WEIGHT.search(code):
        hits.append("light-font-weight")
    if VAGUE_BUTTON.search(code):
        hits.append("alert-ok-button")
    if GENERIC_ALERT.search(code):
        hits.append("alert-generic-title")
    # B1: свой шрифт законен внутри дизайн-системы (шкала и её компоненты),
    # вне её — это уже свой шрифт на экране.
    if CUSTOM_FONT.search(code) and "DesignSystem/" not in path.replace("\\", "/"):
        hits.append("custom-font")
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
            findings.append((path, index + 1, rule_id, lines[index].strip()))
    return findings


def scan_fragment(text: str):
    lines = text.splitlines()
    findings = []
    for index in range(len(lines)):
        for rule_id in check_line("<правка>", lines, index):
            findings.append(("<правка>", index + 1, rule_id, lines[index].strip()))
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


def load_baseline(root: str, path=None):
    """Множество (путь, правило, текст строки) — нарушения на включении сторожа.

    Формат строки — три поля через табуляцию: `путь<TAB>правило<TAB>строка`.
    Номер строки намеренно НЕ хранится: он сдвигается от чужой правки выше по
    файлу, и снимок по номерам ложно объявлял бы старое нарушение новым.
    Пустые строки и строки с `#` пропускаются. Нет файла — пустое множество:
    тогда гейт считает новым всё найденное.
    """
    target = path or os.path.join(root, "Tools", "design-system-baseline.txt")
    if not os.path.isabs(target):
        target = os.path.join(root, target)
    if not os.path.exists(target):
        return set()
    entries = set()
    try:
        with open(target, "r", encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return set()
    for raw in lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) < 3:
            continue
        entries.add((parts[0], parts[1], "\t".join(parts[2:])))
    return entries


def render(findings, baseline=None):
    by_rule = {rule["id"]: rule for rule in RULES}
    # Базовый снимок: нарушения, которые были в коде на момент включения
    # сторожа. Их не роняем сборку — иначе гейт заблокирует всё разом и
    # проект станет несобираемым до конца чистки. Печатаются ВСЕГДА: это
    # список работы, а не «всё в порядке». Роняет только то, чего в снимке
    # не было, — то есть новая правка мимо системы.
    new_findings, known_findings = [], []
    # Ключ сопоставления — (файл, правило, текст строки), БЕЗ номера строки:
    # номера сдвигаются от чужой правки выше по файлу, и снимок по номерам
    # ложно объявил бы старое нарушение новым. Текст строки при сдвиге не
    # меняется, а изменение самой строки — это уже новая правка, её и надо
    # показать.
    for finding in findings:
        rel = finding[0]
        if os.path.isabs(rel):
            try:
                rel = os.path.relpath(rel)
            except ValueError:
                pass
        key = (rel, finding[2], finding[3])
        (known_findings if baseline and key in baseline
         else new_findings).append(finding)
    errors = [f for f in new_findings if by_rule[f[2]]["severity"] == "error"]
    warns = [f for f in new_findings if by_rule[f[2]]["severity"] == "warn"]
    if not findings:
        print("Сторож дизайн-системы: чисто.")
        return 0
    order = {"error": 0, "warn": 1}
    new_findings = sorted(new_findings, key=lambda f: (order[by_rule[f[2]]["severity"]], f[0], f[1]))
    print("Сторож дизайн-системы TaskFlow: НЕ СООТВЕТСТВУЕТ.")
    for path, line, rule_id, _text in new_findings:
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
    if known_findings:
        print("Уже было в коде на момент включения сторожа: %d — ждут чистки, сборку не роняют." % len(known_findings))
        print("Полный список: python3 Tools/design-system-guard.py")
    if errors:
        print("Новых ошибок: %d. Сборка не пройдёт." % len(errors))
    if warns:
        print("Новых предупреждений: %d (сборку не роняют)." % len(warns))
    return 1 if errors else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Сторож дизайн-системы TaskFlow")
    parser.add_argument("--root", default=os.environ.get("SRCROOT") or os.getcwd())
    parser.add_argument("--paths", nargs="*")
    parser.add_argument("--diff", nargs="?", const="HEAD", default=None)
    parser.add_argument("--fragment", action="store_true")
    parser.add_argument("--new-file", default=None)
    parser.add_argument("--folder", action="store_true",
                        help="сканировать локальную папку Sources/ целиком, а не git diff")
    parser.add_argument("--baseline", default=None,
                        help="файл базового снимка (по умолчанию Tools/design-system-baseline.txt)")
    parser.add_argument("--write-baseline", action="store_true",
                        help="перезаписать снимок текущими находками (осознанно, для новых правил)")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    if args.write_baseline:
        rows = []
        for path in sorted(walk_sources(root)):
            for found in scan_file(path):
                rows.append([os.path.relpath(path, root), found[2], found[3]])
        target = args.baseline or os.path.join(root, "Tools", "design-system-baseline.txt")
        if not os.path.isabs(target):
            target = os.path.join(root, target)
        header = BASELINE_HEADER
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(header + "\n".join("\t".join(row) for row in rows) + "\n")
        print("Снимок перезаписан: %d нарушений." % len(rows))
        return 0

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
                findings.append((args.new_file, index + 1, rule_id, new_lines[index].strip()))
        findings.extend(scan_screen_headings(root, overrides={existing: new_text}, affected={existing}))
        return render(findings)

    if args.folder:
        baseline = load_baseline(root, args.baseline)
        findings = []
        for path in sorted(walk_sources(root)):
            findings.extend(scan_file(path))
        findings.extend(scan_screen_headings(root))
        return render(findings, baseline)

    if args.diff is not None:
        added, untracked = diff_added_lines(root, args.diff)
        findings = []
        for path, lineset in added.items():
            findings.extend(scan_file(path, only_lines=lineset))
        for path in untracked:
            findings.extend(scan_file(path))
        findings.extend(scan_screen_headings(root, affected=set(added) | set(untracked)))
        return render(findings)

    if args.paths:
        findings = []
        for path in args.paths:
            full = path if os.path.isabs(path) else os.path.join(root, path)
            findings.extend(scan_file(full))
        findings.extend(scan_screen_headings(root, affected={os.path.abspath(path if os.path.isabs(path) else os.path.join(root, path)) for path in args.paths}))
        return render(findings)

    findings = []
    for path in sorted(walk_sources(root)):
        findings.extend(scan_file(path))
    findings.extend(scan_screen_headings(root))
    return render(findings)


if __name__ == "__main__":
    sys.exit(main())
