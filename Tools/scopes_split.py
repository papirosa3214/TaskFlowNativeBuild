#!/usr/bin/env python3
"""Разбивка реестра работ по месяцам.

Реестр `AGENT-WORK-SCOPES/` разбит на файлы по месяцам: активный месяц —
маленький файл, который правят агенты, старые месяцы — история. Правка
активного файла почти не конфликтует, а в контекст агента попадает вместо
мегабайта двадцать килобайт.

Месяц записи определяется по дате в Lock ID (`-ГГГГММДД`), если её нет —
по дате в тексте строки («Владелец 24.10.2026»), если и её нет — по
ближайшей датированной строке по порядку в файле.

Скрипт идемпотентен: повторный запуск пересобирает те же файлы.

Запуск: python3 Tools/scopes_split.py
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_DIR = ROOT / 'AGENT-WORK-SCOPES'
LEGACY = ROOT / 'AGENT-WORK-SCOPES.md'

TABLE_HEADER = (
    '| Lock ID | Статус | Scope | Что чиним | Разрешённые файлы | Основание '
    '| Исполнитель | Проверка |\n'
    '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
)

LOCK_DATE_RE = re.compile(r'-(\d{8})$')
TEXT_DATE_RE = re.compile(r'\b(\d{2})\.(\d{2})\.(20\d{2})\b')


def read_rows() -> list[str]:
    rows: list[str] = []
    for path in sorted(REGISTRY_DIR.glob('*.md')):
        for line in path.read_text().splitlines():
            if line.startswith('| LOCK-'):
                rows.append(line)
    if LEGACY.exists():
        for line in LEGACY.read_text().splitlines():
            if line.startswith('| LOCK-'):
                rows.append(line)
    return rows


def row_month(line: str) -> str | None:
    lock = line.split(' | ')[0].lstrip('| ').strip()
    m = LOCK_DATE_RE.search(lock)
    if m:
        return m.group(1)[:6]
    found = TEXT_DATE_RE.findall(line)
    if found:
        return sorted(f'{y}{m:02}{d:02}' for d, m, y in found)[0][:6]
    return None


def assign_months(rows: list[str]) -> list[str]:
    months = [row_month(r) for r in rows]
    dated = [i for i, m in enumerate(months) if m]
    if not dated:
        raise SystemExit('не найдено ни одной датированной строки')
    out = []
    for i, m in enumerate(months):
        if m:
            out.append(m)
        else:
            nearest = min(dated, key=lambda j: abs(j - i))
            out.append(months[nearest])
    return out


def month_title(ym: str) -> str:
    return f'{ym[4:6]}.{ym[0:4]}'


def main() -> int:
    rows = read_rows()
    if not rows:
        raise SystemExit('в реестре нет ни одной строки')
    months = assign_months(rows)

    buckets: dict[str, list[str]] = {}
    for row, month in zip(rows, months):
        buckets.setdefault(month, []).append(row)

    REGISTRY_DIR.mkdir(exist_ok=True)
    for path in REGISTRY_DIR.glob('*.md'):
        path.unlink()

    for ym in sorted(buckets):
        items = buckets[ym]
        name = f'{ym[:4]}-{ym[4:6]}'
        others = sorted(m for m in buckets if m != ym)
        links = ', '.join(f'[{m[:4]}-{m[4:6]}]({m[:4]}-{m[4:6]}.md)' for m in others)
        header = (
            f'# Реестр ограничений работ — {month_title(ym)}\n\n'
            f'Активный месяц: **{name}.md**. Правки вносятся сюда, новые строки — '
            f'в начало таблицы.\n\n'
            f'Другие месяцы: {links}.\n\n'
            f'Сводка для чтения (кто что правил и какого типа изменение): '
            f'[реестр-сводка.md](../docs/реестр-сводка.md) — '
            f'пересобирается скриптом `Tools/scopes_digest.py`.\n\n'
            f'{TABLE_HEADER}'
        )
        (REGISTRY_DIR / f'{name}.md').write_text(header + '\n'.join(items) + '\n')
        print(f'{name}.md — {len(items)} строк')

    print(f'всего строк: {len(rows)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
