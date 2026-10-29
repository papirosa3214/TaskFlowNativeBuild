#!/usr/bin/env python3
"""Run graph logic and actual route geometry as macOS XCTest, no simulator.

Before the geometry extraction, adapt the original chainReturnLink using a
recording Path. The legacy branch lets the same regression tests demonstrate
RED against the original production method, not a copied formula.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

source = (root / 'Sources/Features/Task/Detail/PlanReworkCollapse.swift').read_text()
geometry = root / 'Sources/Features/Task/Detail/PlanReturnGeometry.swift'
names = ['PlanReworkCollapseTests']
if '--collapse-only' not in sys.argv and (root / 'Tests/PlanReturnGeometryTests.swift').exists():
    names.append('PlanReturnGeometryTests')
if len(names) == 1:
    pass
elif geometry.exists():
    source += '\n' + geometry.read_text()
else:
    legacy = block((root / 'Sources/Features/Task/Detail/CollaborationPlanView.swift').read_text(), 'private func chainReturnLink(')
    source += '''
struct Path {
    var points: [CGPoint] = []
    mutating func move(to p: CGPoint) { points.append(p) }
    mutating func addLine(to p: CGPoint) { points.append(p) }
    mutating func addQuadCurve(to p: CGPoint, control: CGPoint) { points.append(p) }
}
enum PlanReturnGeometry {
    struct Route { let start, end, headLeft, headRight: CGPoint }
    struct Legacy {
        let nodeWidth: CGFloat
        var nodeHeight: CGFloat { nodeWidth }
''' + legacy + '''
        func route(from: CGPoint, to: CGPoint) -> Route {
            let r = chainReturnLink(from: from, to: to)
            return Route(start: r.line.points.first!, end: r.line.points.last!,
                         headLeft: r.head.points.first!, headRight: r.head.points.last!)
        }
    }
    static func route(from: CGPoint, to: CGPoint, radius: CGFloat, width: CGFloat) -> Route {
        Legacy(nodeWidth: radius * 2).route(from: from, to: to)
    }
}
'''
for name in names:
    source += '\n' + (root / ('Tests/' + name + '.swift')).read_text().replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test')
source += '\nlet suites = [' + ', '.join(n + '.defaultTestSuite' for n in names) + ']\n'
source += '''
for suite in suites { suite.run() }
exit(suites.allSatisfy { $0.testRun!.hasSucceeded } ? 0 : 1)
'''
dev = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
f = dev / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
l = dev / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='plan-rework-') as tmp:
    main = Path(tmp) / 'main.swift'
    main.write_text(source)
    binary = Path(tmp) / 'tests'
    subprocess.run(['swiftc', '-F', str(f), '-I', str(l), '-L', str(l), '-framework', 'XCTest', '-Xlinker', '-rpath', '-Xlinker', str(f), '-Xlinker', '-rpath', '-Xlinker', str(l), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
