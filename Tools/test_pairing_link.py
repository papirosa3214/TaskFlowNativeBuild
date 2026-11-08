#!/usr/bin/env python3
"""Проверка разбора ссылки привязки `taskflow://pair?…` без симулятора.

Почему так: `PairingLink` — чистая логика на Foundation, ей не нужен ни
сервер, ни UI. Компилируем сам файл вместе с фикстурой через `swiftc` на
macOS и гоняем утверждения — тот же приём, что в
`Tools/test_task_swipe_actions.py`. Симулятор по правилу владельца не
трогаем.

Запуск из корня репозитория:
    python3 Tools/test_pairing_link.py

Код возврата 0 — все проверки прошли.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources/Core/Session/PairingLink.swift"

FIXTURE = r"""
import Foundation

var failures = 0

func expectEqual<T: Equatable>(_ actual: T?, _ expected: T?, _ name: String) {
    if actual != expected {
        failures += 1
        print("FAIL \(name): ожидалось \(String(describing: expected)), получено \(String(describing: actual))")
    }
}

func expectNil<T>(_ actual: T?, _ name: String) {
    if let actual {
        failures += 1
        print("FAIL \(name): ожидался отказ, получено \(actual)")
    }
}

let code = String(repeating: "a1b2", count: 8)  // 32 hex

// ── Ссылка из QR ────────────────────────────────────────────────────────
let hostString = "192.168.1.110%3A3001"
let url = URL(string: "taskflow://pair?v=1&code=\(code)&host=\(hostString)")!
let parsed = PairingLink.code(in: url)
expectEqual(parsed?.code, code, "код из QR")
expectEqual(parsed?.host, "192.168.1.110:3001", "адрес из QR раскодирован")

let безАдреса = URL(string: "taskflow://pair?v=1&code=\(code)&host=")!
expectEqual(PairingLink.code(in: безАдреса)?.host, "", "пустой адрес — пустая строка")

let безВерсии = URL(string: "taskflow://pair?code=\(code)")!
expectEqual(PairingLink.code(in: безВерсии)?.code, code, "версию можно не присылать")

expectNil(PairingLink.code(in: URL(string: "taskflow://pair?v=2&code=\(code)")!), "чужая версия схемы")
expectNil(PairingLink.code(in: URL(string: "other://pair?v=1&code=\(code)")!), "чужая схема")
expectNil(PairingLink.code(in: URL(string: "taskflow://voice?code=\(code)")!), "чужой host")
expectNil(PairingLink.code(in: URL(string: "taskflow://pair?v=1")!), "кода нет")
expectNil(PairingLink.code(in: URL(string: "taskflow://pair?v=1&code=\(code.dropLast())")!), "код короче 32")
expectNil(PairingLink.code(in: URL(string: "taskflow://pair?v=1&code=zz\(code.dropFirst(2))")!), "код не hex")

// ── Ручной ввод ────────────────────────────────────────────────────────
expectEqual(PairingLink.normalizedCode(code.uppercased()), code, "регистр не важен")
expectEqual(PairingLink.normalizedCode("  \(code)\n"), code, "пробелы по краям")
expectEqual(PairingLink.normalizedCode("a1b2 a1b2\t a1b2 a1b2 a1b2 a1b2 a1b2 a1b2"), code, "пробелы внутри")
expectEqual(
    PairingLink.normalizedCode("taskflow://pair?v=1&code=\(code)&host=192.168.1.110%3A3001"),
    code,
    "вставленная строка со ссылкой"
)
expectNil(PairingLink.normalizedCode(""), "пустая строка")
expectNil(PairingLink.normalizedCode("12345"), "мусор")
expectNil(PairingLink.normalizedCode(String(repeating: "g", count: 32)), "32 символа, но не hex")

// ── Имя телефона для реестра устройств ────────────────────────────────
if PairingLink.deviceName.isEmpty {
    failures += 1
    print("FAIL имя телефона пустое")
}

if failures == 0 {
    print("OK")
} else {
    print("ПРОВАЛОВ: \(failures)")
    exit(1)
}
"""


def main() -> int:
    if not SOURCE.exists():
        print(f"НЕТ ФАЙЛА: {SOURCE} — проверка невозможна", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        # Верхнеуровневые выражения Swift разрешает только в `main.swift`, иначе
        # `swiftc` ругается «expressions are not allowed at the top level».
        fixture = pathlib.Path(tmp) / "main.swift"
        fixture.write_text(FIXTURE, encoding="utf-8")
        binary = pathlib.Path(tmp) / "pairing_link"
        build = subprocess.run(
            ["swiftc", "-O", str(SOURCE), str(fixture), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if build.returncode != 0:
            print("СБОРКА НЕ УДАЛАСЬ:\n" + build.stderr, file=sys.stderr)
            return 1
        run = subprocess.run([str(binary)], capture_output=True, text=True)
        print(run.stdout.strip())
        if run.stderr.strip():
            print(run.stderr.strip(), file=sys.stderr)
        return run.returncode


if __name__ == "__main__":
    sys.exit(main())
