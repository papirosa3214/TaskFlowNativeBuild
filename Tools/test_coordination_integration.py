#!/usr/bin/env python3
"""Compile real coordination models/state and XCTest on macOS; no simulator.
API transport is a fixture; network contract is checked by server HTTP tests.
"""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
stub='''import Foundation
public enum HTTPMethod { case get, post }
public class APIClient {
 public static var responses: [Data] = []
 public static var paths: [String] = []
 public static var lastBody: Data?
 public init() {}
 public func request<T: Decodable>(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = []) async throws -> T { Self.paths.append(path); return try JSONDecoder().decode(T.self, from: Self.responses.removeFirst()) }
 public func request<T: Decodable, B: Encodable>(_ method: HTTPMethod, _ path: String, body: B) async throws -> T { Self.paths.append(path); Self.lastBody = try JSONEncoder().encode(body); return try JSONDecoder().decode(T.self, from: Self.responses.removeFirst()) }
}
'''
files=['Sources/Core/Networking/APIClient+Coordination.swift','Sources/Features/Coordination/CoordinationCause.swift','Sources/Features/Coordination/CoordinationState.swift']
source=stub+'\n'.join((root/p).read_text() for p in files)
source += '\n' + '\n'.join((root/'Sources/DesignSystem/Hints'/p).read_text() for p in ['HintModels.swift','HintScenarios.swift','HintCenter.swift']) + '\n'
if '--typecheck-ui' in sys.argv:
 source += '\nimport SwiftUI\nenum TFTextFixture { case body, meta, action }\nenum TFSpacing { static let xs: CGFloat = 4 }\nextension View { func tfText(_ role: TFTextFixture) -> some View { self }; func hintAnchor(_ id: String) -> some View { self } }\nextension Color { static var tfRed: Color { .red }; static var tfText: Color { .primary }; static var tfSub: Color { .secondary } }\nenum AppRoute: Hashable { case runtimeProviders }\nfunc routeDestination(_ route: AppRoute) -> some View { Text("fixture") }\n'
 source += '\n' + (root/'Sources/DesignSystem/Components/CoordinationCauseColor.swift').read_text() + '\n' + '\n'.join((root/'Sources/Features/Coordination'/p).read_text() for p in ['ResolutionGraph.swift','ActionBar.swift','CoordinationScreen.swift'])
 with tempfile.TemporaryDirectory(prefix='coordination-ui-typecheck-') as tmp:
  main=Path(tmp)/'panel.swift';main.write_text(source)
  sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
  raise SystemExit(subprocess.run(['swiftc','-typecheck','-target','arm64-apple-ios18.0','-sdk',sdk,str(main)]).returncode)
tests=(root/'Tests/CoordinationIntegrationTests.swift').read_text().replace('@testable import TaskFlow','').replace('    func test','    @objc func test')
source += '\n' + tests + '\nlet suite = XCTestSuite(name: "Coordination")\nsuite.addTest(CoordinationIntegrationTests.defaultTestSuite)\nsuite.addTest(CoordinationTransportTests.defaultTestSuite)\nsuite.run()\nexit(suite.testRun!.hasSucceeded ? 0 : 1)\n'
with tempfile.TemporaryDirectory(prefix='coordination-integration-') as tmp:
 main=Path(tmp)/'main.swift';binary=Path(tmp)/'tests';main.write_text(source)
 dev=Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
 fw=dev/'Platforms/MacOSX.platform/Developer/Library/Frameworks';lib=dev/'Platforms/MacOSX.platform/Developer/usr/lib'
 subprocess.run(['swiftc','-D','COORDINATION_TRANSPORT_FIXTURE','-F',str(fw),'-I',str(lib),'-L',str(lib),'-Xlinker','-rpath','-Xlinker',str(fw),'-Xlinker','-rpath','-Xlinker',str(lib),str(main),'-o',str(binary)],check=True)
 raise SystemExit(subprocess.run([str(binary)]).returncode)
