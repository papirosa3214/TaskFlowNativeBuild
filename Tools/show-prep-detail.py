#!/usr/bin/env python3
"""Подробный разбор прогона структурирования: что именно нарезала модель."""
import json
import sys


def show(path, title):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    print("=" * 72)
    print(title)
    print("=" * 72)

    if "error" in data:
        print("ОШИБКА:", str(data["error"])[:300])
        print()
        return

    card = data.get("card") or {}
    prep = card.get("preparation")
    if not prep:
        print("Подготовки нет:", json.dumps(card, ensure_ascii=False)[:300])
        print()
        return

    print(f"представление: {prep['representation']}")
    print(f"причина: {prep['reason']}")
    print(f"вопрос владельцу: {prep.get('question')}")
    print()

    print("--- Потоки (workstreams):")
    for w in prep["workstreams"]:
        print(f"  • {w['title']}")
        print(f"    результат: {w['result'][:110]}")
        print(f"    роль: {w['role']}   зависит: {w['depends_on']}   параллельно: {w['parallel_with']}")
    print()

    subtasks = card.get("subtasks") or []
    if subtasks:
        print("--- Шаги родительской карточки (subtasks):")
        for s in subtasks:
            print(f"  - {s}")
        print()

    children = card.get("children") or []
    if children:
        print(f"--- Дочерние карточки: {len(children)}")
        for c in children:
            print(f"  • {c['title']}")
            print(f"    роль: {c.get('role')}   после: {c.get('after')}")
            print(f"    результат: {(c.get('result') or '')[:110]}")
            for s in (c.get("subtasks") or []):
                print(f"      шаг: {s}")
    print()


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        path, _, title = arg.partition("=")
        show(path, title or path)