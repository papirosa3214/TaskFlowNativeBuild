#!/usr/bin/env python3
"""Раскладка полок базы знаний и состояние индексации — XCTest под macOS, без симулятора."""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[1]
source = root / "Sources/Core/Models/KnowledgeBase.swift"
if not source.exists():
    raise SystemExit("RED: missing " + str(source))
test = (root / "Tests/KnowledgeBaseTests.swift").read_text()
test = test.replace("@testable import TaskFlow", "").replace("    func test", "    @objc func test")
developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
libraries = developer / "Platforms/MacOSX.platform/Developer/usr/lib"
with tempfile.TemporaryDirectory(prefix="knowledge-base-") as tmp:
    path = Path(tmp)
    (path / "main.swift").write_text(
        test
        + "\nlet suite = KnowledgeBaseTests.defaultTestSuite\nsuite.run()\n"
        + "exit(suite.testRun!.totalFailureCount == 0 ? 0 : 1)\n"
    )
    subprocess.run(
        [
            "swiftc",
            "-F", str(frameworks),
            "-I", str(libraries),
            "-L", str(libraries),
            "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
            "-Xlinker", "-rpath", "-Xlinker", str(libraries),
            str(source), str(path / "main.swift"),
            "-o", str(path / "tests"),
        ],
        check=True,
    )
    raise SystemExit(subprocess.run([str(path / "tests")]).returncode)
