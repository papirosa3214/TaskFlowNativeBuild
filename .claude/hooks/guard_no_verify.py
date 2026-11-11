#!/usr/bin/env python3
"""Запрет обхода стража решений владельца (.githooks/commit-msg), 11.11.2026."""
import json, re, sys
cmd = (json.load(sys.stdin).get("tool_input") or {}).get("command", "")
if re.search(r"\bgit\b[^|;&\n]*\b(commit|push|merge|rebase|cherry-pick|am)\b[^|;&\n]*(--no-verify|\s-n\b)", cmd) \
   or re.search(r"\bgit\b[^|;&\n]*(\bconfig\b|-c)[^|;&\n]*core\.hookspath", cmd, re.I):
    print("Запрещено: обход стража решений владельца (--no-verify / смена core.hooksPath). "
          "Если коммит отклонён — верни удалённое или получи слово владельца.", file=sys.stderr)
    sys.exit(2)
