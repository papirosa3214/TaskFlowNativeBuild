#!/usr/bin/env python3
"""Ответ владельца на сообщение: XCTest на macOS, без симулятора."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / "Sources/Chat/Composer/ChatOwnerReply.swift"
tests = root / "Tests/ChatOwnerReplyTests.swift"

if not source.exists():
    print("RED: ChatOwnerReply.swift отсутствует")
    sys.exit(1)

with tempfile.TemporaryDirectory(prefix="chat-owner-reply-") as tmp:
    main = Path(tmp) / "main.swift"
    binary = Path(tmp) / "tests"
    main.write_text(
        tests.read_text()
        + "\nlet suite = ChatOwnerReplyTests.defaultTestSuite\n"
        + "suite.run()\n"
        + "exit(suite.testRun!.hasSucceeded ? 0 : 1)\n"
    )
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
    libraries = developer / "Platforms/MacOSX.platform/Developer/usr/lib"
    subprocess.run(
        [
            "swiftc",
            "-F", str(frameworks),
            "-I", str(libraries),
            "-L", str(libraries),
            "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
            "-Xlinker", "-rpath", "-Xlinker", str(libraries),
            str(source), str(main), "-o", str(binary),
        ],
        check=True,
    )
    sys.exit(subprocess.run([str(binary)]).returncode)
