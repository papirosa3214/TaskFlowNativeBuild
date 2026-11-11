#!/usr/bin/env python3
"""Запрет обхода стража решений владельца (.githooks/commit-msg), 11.11.2026.
Чтение настройки пути к хукам разрешено, смена и сброс — нет."""
import json, re, sys
cmd = (json.load(sys.stdin).get("tool_input") or {}).get("command", "")
SEG = r"[^|;&\n]*"
bypass = re.search(rf"\bgit\b{SEG}\b(commit|push|merge|rebase|cherry-pick|am)\b{SEG}(--no-verify|\s-n\b)", cmd)
hooks = re.search(rf"\bgit\b{SEG}(--unset{SEG}core\.hookspath|core\.hookspath(=|\s+[^\s;|&]+))", cmd, re.I)
if bypass or hooks:
    print("Запрещено: обход стража решений владельца (--no-verify / смена пути к хукам). "
          "Если коммит отклонён — верни удалённое или получи слово владельца.", file=sys.stderr)
    sys.exit(2)
