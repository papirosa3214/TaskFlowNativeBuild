#!/usr/bin/env python3
"""Разбор ответа /api/task-preparation/prepare: показывает структуру, роли и параллель."""
import json
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    label = path.rsplit("/", 1)[-1].replace("resp_", "").replace(".json", "")
    if "error" in data:
        print(f"{label}: ОШИБКА — {str(data['error'])[:200]}")
        continue

    prep = (data.get("card") or {}).get("preparation")
    if not prep:
        print(f"{label}: подготовки нет")
        continue

    print(f"{label}: {prep['representation']} | вопрос: {prep.get('question')}")
    print(f"   причина: {prep['reason'][:150]}")
    for w in prep["workstreams"]:
        print(f"   роль={w['role']} | {w['title'][:60]}")
        print(f"      depends={w['depends_on']} parallel={w['parallel_with']}")
    print()