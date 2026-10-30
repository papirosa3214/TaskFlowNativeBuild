#!/usr/bin/env python3
"""Compile actual voice-mode logic and hints on macOS; no Simulator."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
parts=[]
mode=root/'Sources/Core/Models/SecretaryVoiceMode.swift'
if mode.exists():parts.append(mode.read_text())
else:raise SystemExit('SecretaryVoiceMode.swift missing')
parts.append((root/'Tests/SecretaryVoiceModeTests.swift').read_text().replace('@testable import TaskFlow','').replace('    func test','    @objc func test'))
for name in ['HintModels','HintScenarios','HintCenter']:
    parts.append((root/f'Sources/DesignSystem/Hints/{name}.swift').read_text())
parts.append((root/'Tests/HintCenterTests.swift').read_text().replace('@testable import TaskFlow','').replace('    func test','    @objc func test'))
parts.append('let suite=SecretaryVoiceModeTests.defaultTestSuite\nsuite.run()\nTask { @MainActor in let hints=XCTestSuite(name:"Voice modes hint"); hints.addTest(HintCenterTests(selector:#selector(HintCenterTests.testVoiceModesHintCompletes))); hints.run(); exit(suite.testRun!.hasSucceeded && hints.testRun!.hasSucceeded ? 0 : 1) }; RunLoop.main.run()')
with tempfile.TemporaryDirectory(prefix='voice-modes-') as tmp:
    main=Path(tmp)/'main.swift';main.write_text('\n'.join(parts));binary=Path(tmp)/'tests'
    dev=Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
    frameworks=dev/'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries=dev/'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run(['swiftc','-F',str(frameworks),'-I',str(libraries),'-L',str(libraries),'-Xlinker','-rpath','-Xlinker',str(frameworks),'-Xlinker','-rpath','-Xlinker',str(libraries),str(main),'-o',str(binary)],check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
