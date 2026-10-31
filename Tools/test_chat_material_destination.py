#!/usr/bin/env python3
"""Run the production reference resolver and its XCTest suite on macOS."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
tests = (root / 'Tests/ChatMaterialDestinationTests.swift').read_text()
tests = tests.replace('@testable import TaskFlow', '')
tests = re.sub(r'    func (test\w+)\(', r'    @objc func \1(', tests)
source = (root / 'Sources/ChatComponents/Panels/ChatMaterialDestination.swift').read_text()
program = source + '\n' + tests + '''
let suite = ChatMaterialDestinationTests.defaultTestSuite
suite.run()
exit(suite.testRun!.hasSucceeded ? 0 : 1)
'''
developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='material-destination-') as folder:
    main = Path(folder) / 'main.swift'
    main.write_text(program)
    binary = Path(folder) / 'tests'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
                    '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath',
                    '-Xlinker', str(libraries), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
