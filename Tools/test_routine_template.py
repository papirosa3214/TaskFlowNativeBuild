#!/usr/bin/env python3
"""Run real routine editor/payload and hints on macOS, no simulator."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
paths = ['Sources/Core/Common/CalendarDateMath.swift', 'Sources/Core/Common/DateFormats.swift',
         'Sources/Core/Models/Schedule.swift', 'Sources/Features/Routines/RoutineFormat.swift',
         'Sources/Features/Routines/RoutineFormViewModel.swift', 'Tests/RoutineTemplateTests.swift']
with tempfile.TemporaryDirectory(prefix='routine-template-') as tmp:
    binary = Path(tmp) / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', '-D', 'ROUTINE_TEMPLATE_HOST_TEST',
                    *[str(root / p) for p in paths], '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)]).returncode
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    main = Path(tmp) / 'main.swift'
    tests = (root / 'Tests/HintCenterTests.swift').read_text().replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test')
    main.write_text(tests + '\nMainActor.assumeIsolated {\nlet suite = XCTestSuite(name: "Routine hint")\nsuite.addTest(HintCenterTests(selector: #selector(HintCenterTests.testRoutineEditingHintCompletes)))\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n}\n')
    hint_sources = [root / ('Sources/DesignSystem/Hints/' + n + '.swift') for n in ['HintModels', 'HintScenarios', 'HintCenter']]
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), *map(str, hint_sources), str(main), '-o', str(binary)], check=True)
    result |= subprocess.run([str(binary)]).returncode
    raise SystemExit(result)
