#!/usr/bin/env python3
"""Сводка по реестру работ.

Реестр разбит по месяцам: `AGENT-WORK-SCOPES/ГГГГ-ММ.md` (активный месяц —
`2026-11.md`). Записи из всех файлов складываются в сводку: что в работе,
что сломано, кто что правил и какого это типа изменение (код / тесты /
документы / инфраструктура).

Запуск: python3 Tools/scopes_digest.py
Результат: docs/реестр-сводка.md
"""
from __future__ import annotations

import datetime
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_DIR = ROOT / 'AGENT-WORK-SCOPES'
OUT = ROOT / 'docs' / 'реестр-сводка.md'

STATUSES = ('REVIEW', 'IN_PROGRESS', 'BROKEN', 'CANCELLED', 'DONE')
KNOWN_AUTHORS = (
    'Mavis', 'Codex', 'Codex (droid)', 'Claude', 'Разработчик (builder)',
    'Разработчик', 'Помощник владельца', 'Секретарь', 'Дизайнер',
    'QA', 'Архитектор', 'Инфраструктура',
)

DATE_RE = re.compile(r'-(\d{8})$')


def classify(files_cell: str) -> tuple[str, list[str]]:
    """Тип изменения по списку файлов: что менялось на самом деле."""
    low = files_cell.lower()
    kinds: list[str] = []
    if 'sources/' in low:
        kinds.append('код')
    if 'tests/' in low or 'snapshottests/' in low:
        kinds.append('тесты')
    if 'docs/' in low or '.md' in low:
        kinds.append('документы')
    if 'tools/' in low or 'project.yml' in low or '.gitignore' in low:
        kinds.append('инфра')
    if not kinds:
        kinds.append('прочее')
    return '+'.join(kinds), kinds


PATH_RE = re.compile(
    r'(Sources|Tests|UITests|SnapshotTests|Widgets|Resources|Tools|docs|spec|archive|'
    r'mockups|Broadcast|VoiceMessageLab)/|\.(swift|md|yml|yaml|json|sh|plist|py)\b'
)
SHORT_ID_RE = re.compile(r'^[A-Z0-9][A-Z0-9\-_]{2,40}$')
AUTHOR_RE = re.compile(r"^[A-Za-zА-Яа-я][A-Za-zА-Яа-я0-9 .()（）\-–]{0,44}$")
NOT_AUTHOR_WORDS = (
    'RED', 'GREEN', 'ПРОВЕРКИ', 'Проверки', 'python3', 'xcodebuild', 'СДЕЛАНО',
    'Сборка', 'Сторож', 'Цель', 'Основание', 'Владелец',
)


def path_hits(cell: str) -> int:
    return len(PATH_RE.findall(cell))


def looks_like_files(cell: str) -> bool:
    c = cell.strip()
    if not c:
        return False
    return bool(PATH_RE.search(c)) and (c.startswith('`') or ', ' in c or c.endswith('`'))


def looks_like_author(cell: str) -> bool:
    c = cell.strip()
    if not c or len(c) > 45:
        return False
    if '`' in c or not AUTHOR_RE.match(c):
        return False
    return not any(w.lower() in c.lower() for w in NOT_AUTHOR_WORDS)


def parse_row(line: str) -> dict | None:
    parts = line.rstrip('\n').split(' | ')
    if len(parts) < 5:
        return None
    # Первая ячейка может быть в обратных кавычках — так пишут новые строки;
    # без снятия кавычек такие записи молча выпадали из сводки.
    lock = parts[0].lstrip('| ').strip().strip('`').strip()
    if not lock.startswith('LOCK-'):
        return None
    status = parts[1].strip().strip('`').strip()

    # Список файлов: по конвенции ячейка начинается с обратной кавычки и
    # перечисляет пути. Внутри описания тоже встречаются backtick-вставки,
    # поэтому берём первую ячейку, где путей действительно несколько.
    files_idx = None
    for i in range(2, len(parts)):
        c = parts[i].strip()
        if c.startswith('`') and path_hits(c) >= 2:
            files_idx = i
            break
    if files_idx is None:
        for i in range(2, len(parts)):
            if looks_like_files(parts[i]):
                files_idx = i
                break
    if files_idx is None:
        files_idx = min(len(parts) - 1, 3)

    what_cells = [c.strip() for c in parts[2:files_idx]]
    short = ''
    if what_cells and SHORT_ID_RE.match(what_cells[0]) and len(what_cells) > 1:
        short = what_cells[0]
        what_cells = what_cells[1:]
    what = ' '.join(what_cells).strip()
    files = parts[files_idx].strip().strip('`')

    author = ''
    for cell in parts[files_idx + 1:]:
        c = cell.strip()
        if c in KNOWN_AUTHORS:
            author = c
            break
    if not author:
        for cell in parts[files_idx + 1:]:
            if looks_like_author(cell):
                author = cell.strip()
                break

    date = DATE_RE.search(lock)
    date = date.group(1) if date else ''

    kind, _ = classify(files)
    return {
        'lock': lock, 'status': status, 'short': short, 'what': what,
        'files': files, 'author': author, 'date': date, 'kind': kind,
    }


def collect() -> list[dict]:
    rows = []
    for path in sorted(REGISTRY_DIR.glob('*.md')):
        for line in path.read_text().splitlines():
            row = parse_row(line)
            if row:
                row['file'] = path.name
                rows.append(row)
    return rows


def fmt_date(d: str) -> str:
    return f'{d[6:8]}.{d[4:6]}.{d[0:4]}' if len(d) == 8 else '—'


def age_days(date: str, today: datetime.date) -> int | None:
    if len(date) != 8:
        return None
    try:
        d = datetime.date(int(date[:4]), int(date[4:6]), int(date[6:8]))
    except ValueError:
        return None
    return (today - d).days


def one_line(text: str, limit: int = 150) -> str:
    text = re.sub(r'\s+', ' ', text).strip()
    text = text.replace('|', '/')
    return text if len(text) <= limit else text[:limit - 1].rstrip() + '…'


def main() -> int:
    rows = collect()
    counts: dict[str, int] = {}
    for r in rows:
        counts[r['status']] = counts.get(r['status'], 0) + 1

    by_status: dict[str, list[dict]] = {}
    for r in rows:
        by_status.setdefault(r['status'], []).append(r)
    for v in by_status.values():
        v.sort(key=lambda r: (r['date'], r['lock']), reverse=True)

    kinds: dict[str, int] = {}
    for r in rows:
        kinds[r['kind']] = kinds.get(r['kind'], 0) + 1

    lines: list[str] = []
    lines.append('# Сводка по реестру работ')
    lines.append('')
    lines.append('Сгенерировано из `AGENT-WORK-SCOPES/ГГГГ-ММ.md` — скриптом `Tools/scopes_digest.py`.')
    lines.append('Реестр остаётся источником правды; эта сводка — только для чтения.')
    lines.append('')
    lines.append(f'Записей: **{len(rows)}**. Обновлено автоматически, вручную не правится.')
    lines.append('')
    lines.append('## Статусы')
    lines.append('')
    lines.append('| Статус | Записей | Что значит |')
    lines.append('| --- | --- | --- |')
    meanings = {
        'IN_PROGRESS': 'работа идёт, файлы разрешены к правке',
        'REVIEW': 'сделано, ждёт приёмки владельца',
        'BROKEN': 'запись о том, что сломалось',
        'CANCELLED': 'отменено',
        'DONE': 'закрыто',
    }
    for s in STATUSES:
        if counts.get(s):
            lines.append(f'| {s} | {counts[s]} | {meanings.get(s, "")} |')
    lines.append('')
    lines.append('## Что менялось по типу')
    lines.append('')
    lines.append('| Тип | Записей |')
    lines.append('| --- | --- |')
    for k, v in sorted(kinds.items(), key=lambda kv: -kv[1]):
        lines.append(f'| {k} | {v} |')
    lines.append('')

    today = datetime.date.today()
    stale_days = 3

    for status, title in (
        ('IN_PROGRESS', 'Сейчас в работе'),
        ('BROKEN', 'Сломанное'),
        ('CANCELLED', 'Отменённое'),
    ):
        items = by_status.get(status, [])
        if not items:
            continue
        lines.append(f'## {title} ({len(items)})')
        lines.append('')
        lines.append('| Дата | Запись | Что | Тип | Автор |')
        lines.append('| --- | --- | --- | --- | --- |')
        for r in items:
            lines.append(
                f'| {fmt_date(r["date"])} | `{r["lock"]}` | {one_line(r["what"], 110)} '
                f'| {r["kind"]} | {r["author"] or "—"} |'
            )
        lines.append('')

    stale = [r for r in by_status.get('IN_PROGRESS', [])
             if (age_days(r['date'], today) or 0) > stale_days]
    if stale:
        stale.sort(key=lambda r: age_days(r['date'], today) or 0, reverse=True)
        lines.append(f'## Замерло в работе ({len(stale)})')
        lines.append('')
        lines.append(f'Записи в статусе `IN_PROGRESS` старше {stale_days} дней — их можно '
                     f'закрыть или перевести в `REVIEW`.')
        lines.append('')
        lines.append('| Дней висит | Запись | Что | Автор |')
        lines.append('| --- | --- | --- | --- |')
        for r in stale:
            days = age_days(r['date'], today) or 0
            lines.append(
                f'| {days} | `{r["lock"]}` | {one_line(r["what"], 100)} '
                f'| {r["author"] or "—"} |'
            )
        lines.append('')

    lines.append(f'## Все записи ({len(rows)})')
    lines.append('')
    lines.append('| Дата | Запись | Статус | Что | Тип | Автор | Файл |')
    lines.append('| --- | --- | --- | --- | --- | --- | --- |')
    for r in sorted(rows, key=lambda r: (r['date'], r['lock']), reverse=True):
        lines.append(
            f'| {fmt_date(r["date"])} | `{r["lock"]}` | {r["status"]} '
            f'| {one_line(r["what"], 130)} | {r["kind"]} | {r["author"] or "—"} '
            f'| `{r["file"]}` |'
        )
    lines.append('')

    OUT.write_text('\n'.join(lines))
    print(f'записей: {len(rows)} → {OUT.relative_to(ROOT)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
