#!/usr/bin/env python3
"""xAI must be routable for «Модели ролям» (LOCK-XAI-SUBSCRIPTION-RUNTIME-20261103)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Sources/Features/Settings/RoleModelsSection.swift"


def main() -> int:
    text = SRC.read_text(encoding="utf-8")
    routable = re.search(
        r"private static let routable: Set<String> = \[(.*?)]",
        text,
        re.S,
    )
    if not routable:
        print("FAIL: routable set not found", file=sys.stderr)
        return 1
    blob = routable.group(1)
    if '"xai"' not in blob:
        print("FAIL: xai missing from routable", file=sys.stderr)
        return 1
    if 'case "xai": "xAI · подписка Grok"' not in text:
        print("FAIL: xai providerTitle missing", file=sys.stderr)
        return 1
    print("PASS: xai routable + title")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
