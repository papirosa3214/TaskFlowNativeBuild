#!/usr/bin/env python3
"""После запуска из Xcode (mcp__xcode__RunProject) проверяет, на какой
симулятор встала свежая сборка. Владелец 12.11.2026: «ты опять запускаешь не
тот симулятор». Xcode сам сбрасывает назначение на iPhone 18 Pro, и проверка
уходила в старую копию приложения на iPhone Air.

Нужный — iPhone Air на iOS 27.0 (как телефон владельца, он же в панели).
Сравниваем время установки приложения на всех загруженных симуляторах:
самая свежая копия должна лежать на нём. Иначе — сигнал модели и владельцу.
"""
import json
import os
import subprocess
import sys

TARGET_UDID = "9FF78D89-EE84-4914-AA56-D0A72D1AF43A"
TARGET_NAME = "iPhone Air (27.0)"
BUNDLE = "com.maksim.taskflow.native"


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=10)


def main():
    try:
        sys.stdin.read()
    except Exception:
        pass
    try:
        booted = json.loads(run("xcrun", "simctl", "list", "devices", "booted", "-j").stdout)
    except Exception:
        return
    installs = []  # (mtime, udid, name)
    for runtime, devices in booted.get("devices", {}).items():
        for d in devices:
            udid = d.get("udid")
            res = run("xcrun", "simctl", "get_app_container", udid, BUNDLE)
            path = res.stdout.strip()
            if res.returncode == 0 and path and os.path.exists(path):
                ver = runtime.rsplit("iOS-", 1)[-1].replace("-", ".")
                installs.append((os.path.getmtime(path), udid, f"{d.get('name')} ({ver})"))
    if not installs:
        return
    installs.sort(reverse=True)
    _, udid, name = installs[0]
    if udid == TARGET_UDID:
        return
    msg = (f"Сборка запущена НЕ на том симуляторе: {name}. Нужен {TARGET_NAME} "
           f"({TARGET_UDID}). Сделай mcp__xcode__XcodeSwitchRunDestination "
           f"displayTitle=\"{TARGET_NAME}\" и запусти RunProject заново; кадры "
           f"с {TARGET_NAME} сейчас показывают старую сборку. Чужой симулятор "
           f"не выключай без слова владельца.")
    print(json.dumps({
        "systemMessage": f"⚠️ Сборка ушла на {name}, а не на {TARGET_NAME}",
        "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg},
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
