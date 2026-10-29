#!/usr/bin/env python3
"""Ужимает иконки Composio: серая картинка с альфой → палитра на 16 цветов.

Рендер иконок делает `render.swift` (WebKit рисует SVG серым). Здесь только
размер: палитра с альфой втрое легче серой+альфы, а на экране иконка всё
равно красится одним цветом (шаблон). Если PIL недоступен — файлы остаются
как есть, приложение работает и с ними.
"""
from pathlib import Path
import sys

try:
    from PIL import Image
except ImportError:
    print("PIL недоступен — иконки оставлены без оптимизации")
    raise SystemExit(0)

folder = Path(sys.argv[1] if len(sys.argv) > 1 else "Resources/ComposioIcons")
before = after = 0
count = 0
for path in sorted(folder.glob("*.png")):
    size_before = path.stat().st_size
    with Image.open(path) as image:
        rgba = image.convert("RGBA")
        # 16 цветов: серый силуэт и его полупрозрачные края.
        packed = rgba.quantize(colors=16, method=Image.FASTOCTREE, dither=Image.NONE)
        tmp = path.with_suffix(".tmp.png")
        packed.save(tmp, "PNG", optimize=True)
    size_after = tmp.stat().st_size
    if size_after < size_before:
        tmp.replace(path)
        after += size_after
    else:
        tmp.unlink()
        after += size_before
    before += size_before
    count += 1

print(f"иконок: {count}, было {before / 1024 / 1024:.2f} МБ, стало {after / 1024 / 1024:.2f} МБ")
