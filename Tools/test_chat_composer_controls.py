#!/usr/bin/env python3
"""Run real chat-control Foundation policies and XCTest on macOS, no Simulator."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
model=root/'Sources/Core/Models/ChatComposerControls.swift'
source=model.read_text() if model.exists() else ''
if not model.exists():
    old=(root/'Sources/Core/Networking/APIClient+Roles.swift').read_text()
    a=old.index('public struct RoleModelOption:'); b=old.index('\n}',a)+2
    source='import Foundation\n'+old[a:b]
source+='\n'+(root/'Tests/ChatComposerControlsTests.swift').read_text().replace('@testable import TaskFlow','').replace('    func test','    @objc func test')
source+='\nlet suite = ChatComposerControlsTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
d=Path(subprocess.check_output(['xcode-select','-p'],text=True).strip());f=d/'Platforms/MacOSX.platform/Developer/Library/Frameworks';l=d/'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='tf-composer-controls-') as tmp:
    p=Path(tmp);(p/'main.swift').write_text(source)
    subprocess.run(['swiftc','-F',str(f),'-I',str(l),'-L',str(l),'-Xlinker','-rpath','-Xlinker',str(f),'-Xlinker','-rpath','-Xlinker',str(l),str(p/'main.swift'),'-o',str(p/'tests')],check=True)
    raise SystemExit(subprocess.run([str(p/'tests')]).returncode)
