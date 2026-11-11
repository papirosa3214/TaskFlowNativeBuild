#!/usr/bin/env python3
"""Превью вложения в ленте — фиксированная рамка, без симулятора."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
src = (root / "Sources/Chat/Feed/ChatFeedParts.swift").read_text()

def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)

if "enum ChatAttachmentPreviewLayout" not in src:
    fail("нет ChatAttachmentPreviewLayout")
if not re.search(r"static let width: CGFloat = 220", src):
    fail("width не 220")
if not re.search(r"static let height: CGFloat = 140", src):
    fail("height не 140")

block = src.split("struct ChatAttachmentImage")[1].split("struct ChatFileChip")[0]
if ".frame(maxWidth: 220)" in block:
    fail("maxWidth без высоты — строка прыгнет")
if ".frame(height: 140)" in block and "ChatAttachmentPreviewLayout.height" not in block:
    fail("заглушка своей высоты, готовая картинка — другой")
if ".frame(width: ChatAttachmentPreviewLayout.width, height: ChatAttachmentPreviewLayout.height)" not in block:
    fail("рамка не общая на заглушку и картинку")
print("ChatAttachmentImage: рамка 220×140 — OK")
