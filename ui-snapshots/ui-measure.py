#!/usr/bin/env python3
"""Геометрия экранов TaskFlow на iPhone Air Simulator.

Снимает кадр каждого основного экрана через `simctl io screenshot` и меряет
его численно: размер экрана, цвет фона, центральная кнопка «+», полосы тёмного
текста, полоса нижней навигации. Всё в пунктах и миллиметрах.

Миллиметры считаются по плотности пикселей iPhone Air: 460 ppi, 3 px = 1 pt,
то есть 1 pt = 25.4 / (460/3) = 0.16565 мм. Габариты корпуса (74.7 мм) для
этого НЕ берутся — ширина корпуса больше ширины экрана.

Зависимостей нет: PNG декодируется через zlib и штатные фильтры. На машине
нет ни PIL, ни ImageMagick.

    python3 ui-measure.py                 # весь список экранов
    python3 ui-measure.py overview notes  # только указанные
"""

import json
import os
import struct
import subprocess
import sys
import time
import zlib
from collections import Counter

BUNDLE = "com.maksim.taskflow.native"
PPI = 460.0
PT_MM = 25.4 / (PPI / 3.0)
SETTLE = 6.0  # сек на загрузку стора: внутри роута стоит пауза 2 с плюс сеть

ROUTES = [
    ("overview", ""),          # стартовый экран, без переменной окружения
    ("projects", "projects"),
    ("alltasks", "alltasks"),
    ("today", "today"),
    ("upcoming", "upcoming"),
    ("notifications", "notifications"),
    ("chat", "chat"),
    ("agents", "agents"),
    ("models", "models"),
    ("notes", "notes"),
    ("settings", "settings"),
    ("serversettings", "serversettings"),
]

HERE = os.path.dirname(os.path.abspath(__file__))
SCREENS = os.path.join(HERE, "screens")
DATA = os.path.join(HERE, "data")


# --------------------------------------------------------------------------- PNG

def load_png(path):
    """Вернуть (width, height, channels, pixel bytes) без внешних библиотек."""
    raw_file = open(path, "rb").read()
    if raw_file[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("не PNG: %s" % path)
    pos, idat, width = 8, b"", None
    while pos < len(raw_file):
        length = struct.unpack(">I", raw_file[pos:pos + 4])[0]
        kind = raw_file[pos + 4:pos + 8]
        body = raw_file[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
            if depth != 8 or color not in (2, 6):
                raise ValueError("поддерживается только 8 бит, RGB/RGBA")
            channels = 3 if color == 2 else 4
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length

    data = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(height * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        filt = data[p]
        p += 1
        line = bytearray(data[p:p + stride])
        p += stride
        if filt == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif filt == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif filt == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(a + b - c - a), abs(a + b - c - b), abs(a + b - c - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, out


# ------------------------------------------------------------------------ замеры

def rect(x0, y0, x1, y1):
    """Прямоугольник в пунктах и миллиметрах от левого верхнего угла экрана."""
    return {
        "x_pt": round(x0 / 3.0, 1), "y_pt": round(y0 / 3.0, 1),
        "x_mm": round(x0 / 3.0 * PT_MM, 1), "y_mm": round(y0 / 3.0 * PT_MM, 1),
        "w_pt": round((x1 - x0) / 3.0, 1), "h_pt": round((y1 - y0) / 3.0, 1),
        "w_mm": round((x1 - x0) / 3.0 * PT_MM, 1), "h_mm": round((y1 - y0) / 3.0 * PT_MM, 1),
        "right_mm": None, "bottom_mm": None,
    }


def measure(path):
    width, height, channels, buf = load_png(path)

    def px(x, y):
        i = (y * width + x) * channels
        return buf[i], buf[i + 1], buf[i + 2]

    result = {
        "screenshot": os.path.relpath(path, HERE),
        "screen": {
            "px": [width, height],
            "pt": [width // 3, height // 3],
            "mm": [round(width / 3.0 * PT_MM, 1), round(height / 3.0 * PT_MM, 1)],
            "mm_per_pt": round(PT_MM, 5),
        },
    }

    # фон — самый частый цвет на сетке 6 px
    hist = Counter()
    for y in range(0, height, 6):
        for x in range(0, width, 6):
            hist[px(x, y)] += 1
    bg = hist.most_common(1)[0][0]
    result["background_rgb"] = list(bg)
    # Тема выводится из фона, а не из настройки симулятора: симулятор
    # переключается сам (например, по часам), и набор замеров обязан быть
    # однородным, иначе половина экранов посчитается пустыми.
    dark_theme = (bg[0] * 299 + bg[1] * 587 + bg[2] * 114) / 1000.0 < 128
    result["theme"] = "dark" if dark_theme else "light"

    def is_ink(r, g, b):
        if dark_theme:
            return r > 190 and g > 190 and b > 190
        return r < 90 and g < 90 and b < 90

    # Кнопка «+» — круг в правой нижней зоне. Работает не цвет, а связность:
    # в этой области всё, что отличается от фона, — либо панель навигации,
    # либо сама кнопка, и нужная из них правее. Цветовые признаки тут отменены:
    # в тёмной теме заливка светлеет, ячейки тепловой карты красные, а линия
    # текущего времени длиннее кнопки площадью.
    rx0, ry0 = int(width * 0.72), int(height * 0.88)
    mask = bytearray(width * height)
    for y in range(ry0, height):
        for x in range(rx0, width):
            r, g, b = px(x, y)
            if abs(r - bg[0]) > 12 or abs(g - bg[1]) > 12 or abs(b - bg[2]) > 12:
                mask[y * width + x] = 1
    seen = bytearray(width * height)
    comps = []
    for y in range(ry0, height, 2):
        for x in range(rx0, width, 2):
            if mask[y * width + x] and not seen[y * width + x]:
                stack, pts = [(x, y)], []
                seen[y * width + x] = 1
                while stack:
                    cx, cy = stack.pop()
                    pts.append((cx, cy))
                    for nx, ny in ((cx + 2, cy), (cx - 2, cy), (cx, cy + 2), (cx, cy - 2)):
                        if rx0 <= nx < width and ry0 <= ny < height \
                                and mask[ny * width + nx] and not seen[ny * width + nx]:
                            seen[ny * width + nx] = 1
                            stack.append((nx, ny))
                if len(pts) > 200:
                    xs = [p[0] for p in pts]
                    ys = [p[1] for p in pts]
                    comps.append((max(xs), len(pts), min(xs), max(xs), min(ys), max(ys)))
    if comps:
        comps.sort(reverse=True)
        _, n, bx0, bx1, by0, by1 = comps[0]
        w_px, h_px = bx1 - bx0, by1 - by0
        d_mm = round(w_px / 3.0 * PT_MM, 1)
        roundness = round(min(w_px, h_px) / max(1, max(w_px, h_px)), 2)
        # Кнопка «+» — круг около 10 мм. Если найденная область не круг или
        # размер не похож на кнопку, значит в неё слипся соседний элемент
        # (панель навигации или её тень). Такую находку не записываем как
        # геометрию кнопки — проверенного значения лучше нет, чем неверное.
        if roundness >= 0.85 and 7.0 <= d_mm <= 14.0:
            box = rect(bx0, by0, bx1, by1)
            box["center_pt"] = [round((bx0 + bx1) / 6.0, 1), round((by0 + by1) / 6.0, 1)]
            box["center_mm"] = [round((bx0 + bx1) / 6.0 * PT_MM, 1),
                                round((by0 + by1) / 6.0 * PT_MM, 1)]
            box["right_mm"] = round((width - bx1) / 3.0 * PT_MM, 1)
            box["bottom_mm"] = round((height - by1) / 3.0 * PT_MM, 1)
            box["d_mm"] = d_mm
            box["round"] = roundness
            box["rgb"] = list(px((bx0 + bx1) // 2, (by0 + by1) // 2))
            result["accent_button"] = box
        else:
            result["accent_button"] = None
            result["accent_button_rejected"] = {
                "why": "область не круг или не размер кнопки",
                "d_mm": d_mm, "round": roundness,
                "x_mm": round(bx0 / 3.0 * PT_MM, 1), "y_mm": round(by0 / 3.0 * PT_MM, 1),
            }
        result["accent_button_blobs"] = len(comps)
    else:
        result["accent_button"] = None
        result["accent_button_blobs"] = 0

    # Нижняя навигация — панель слева от кнопки: строки, где в нижней зоне
    # много пикселей, отличных от фона.
    px0, py0 = 0, int(height * 0.86)
    band_rows = []
    for y in range(py0, height, 2):
        cnt, xs = 0, []
        for x in range(px0, int(width * 0.72)):
            r, g, b = px(x, y)
            if abs(r - bg[0]) > 12 or abs(g - bg[1]) > 12 or abs(b - bg[2]) > 12:
                cnt += 1
                xs.append(x)
        if cnt > int(width * 0.72) * 0.25:
            band_rows.append((y, min(xs), max(xs)))
    if len(band_rows) > 20:
        bar = rect(min(r[1] for r in band_rows), band_rows[0][0],
                   max(r[2] for r in band_rows), band_rows[-1][0] + 2)
        bar["bottom_mm"] = round((height - band_rows[-1][0] - 2) / 3.0 * PT_MM, 1)
        result["tab_bar"] = bar
    else:
        result["tab_bar"] = None

    # полосы тёмного текста: проекция по Y, extent по X
    bands, current = [], []
    prev_y = None
    for y in range(0, height, 3):
        xs = []
        for x in range(0, width, 3):
            r, g, b = px(x, y)
            if is_ink(r, g, b):
                xs.append(x)
        if len(xs) >= 3:
            if prev_y is not None and y - prev_y > 12 and current:
                bands.append(current)
                current = []
            current.append((y, min(xs), max(xs)))
            prev_y = y
        else:
            if current:
                bands.append(current)
                current, prev_y = [], None
    if current:
        bands.append(current)

    texts = []
    for band in bands:
        y0 = band[0][0]
        y1 = band[-1][0]
        x0 = min(b[1] for b in band)
        x1 = max(b[2] for b in band)
        texts.append(rect(x0, y0, x1 + 3, y1 + 3))
    result["text_bands"] = texts
    result["text_bands_count"] = len(texts)

    return result


# ------------------------------------------------------------------------ прогон

def udid():
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "booted"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "Booted" in line and "iPhone Air" in line:
            return line.split("(")[1].split(")")[0]
    raise SystemExit("iPhone Air не загружен")


def capture(device, route, out_png):
    subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE],
                   capture_output=True)
    env = dict(os.environ)
    if route:
        env["SIMCTL_CHILD_TASKFLOW_DEBUG_ROUTE"] = route
    subprocess.run(["xcrun", "simctl", "launch", device, BUNDLE],
                   capture_output=True, env=env)
    time.sleep(SETTLE)
    subprocess.run(["xcrun", "simctl", "io", device, "screenshot", out_png],
                   capture_output=True, check=True)


def main():
    wanted = set(sys.argv[1:])
    routes = [r for r in ROUTES if not wanted or r[0] in wanted]
    if not routes:
        raise SystemExit("нет таких экранов: %s" % ", ".join(sorted(wanted)))

def main():
    remeasure = "--remeasure" in sys.argv
    wanted = {a for a in sys.argv[1:] if not a.startswith("--")}
    routes = [r for r in ROUTES if not wanted or r[0] in wanted]
    if not routes:
        raise SystemExit("нет таких экранов: %s" % ", ".join(sorted(wanted)))

    os.makedirs(SCREENS, exist_ok=True)
    os.makedirs(DATA, exist_ok=True)
    device = udid()
    # Системную тему НЕ навязываем: у приложения своя сохранённая настройка
    # (`taskflow_appearance` в UserDefaults, по умолчанию тёмная), и `simctl ui
    # appearance` на неё не влияет. Мерим то, что приложение реально рисует, а
    # вычисленную тему кладём в JSON — набор остаётся сопоставимым.
    if remeasure:
        print("режим пересчёта: берём готовые кадры, симулятор не трогаем, экранов: %d"
              % len(routes))
    else:
        print("устройство: %s, экранов: %d, ожидание %.0f с на экран"
              % (device, len(routes), SETTLE))

    digests = {}
    for name, route in routes:
        png = os.path.join(SCREENS, "%s.png" % name)
        if remeasure:
            # пересчёт по уже снятым кадрам: симулятор и приложение не трогаются
            if not os.path.exists(png):
                print("  %-14s НЕТ КАДРА %s" % (name, os.path.basename(png)))
                continue
        else:
            capture(device, route, png)
        data = measure(png)
        data["name"] = name
        data["debug_route"] = route or "(стартовый экран)"
        data["device"] = device
        data["remeasured_without_capture"] = bool(remeasure)
        with open(os.path.join(DATA, "%s.json" % name), "w") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)

        import hashlib
        digest = hashlib.md5(open(png, "rb").read()).hexdigest()
        twin = digests.get(digest)
        digests[digest] = name
        button = data["accent_button"]
        bar = data.get("tab_bar")
        print("  %-14s полос %2d  «+» %-13s d=%-5s  таббар %s%s" % (
            name, data["text_bands_count"],
            ("%.1f/%.1f мм" % tuple(button["center_mm"])) if button else "—",
            ("%.1f мм" % button["d_mm"]) if button else "—",
            ("%.1f–%.1f мм" % (bar["y_mm"], bar["y_mm"] + bar["h_mm"])) if bar else "НЕТ",
            "  ! КАДР СОВПАЛ С %s" % twin if twin else ""))


if __name__ == "__main__":
    main()
