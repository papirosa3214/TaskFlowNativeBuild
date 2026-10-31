#!/usr/bin/env python3
"""Execute real reveal history/draw control flow using a recording context on macOS.

The drawing sink is a test double; this does not measure SwiftUI layout or FPS.
"""
from pathlib import Path
import subprocess
import tempfile
import re

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


source = (ROOT / 'Sources/Features/Roles/RoleLiveTurnView.swift').read_text()
stubs = '''
import Foundation
enum RoleLiveTextPacer { static let minRate = 30.0 }
enum Text { typealias Layout = [[[Int]]] }
protocol TextRenderer {}
final class DrawRecord { var lines = 0; var glyphs = 0 }
struct GraphicsContext {
    var record = DrawRecord()
    var opacity = 1.0
    mutating func draw(_ line: [[Int]]) { record.lines += 1 }
    mutating func draw(_ glyph: Int) { record.glyphs += 1 }
}
struct ForEach<Data: RandomAccessCollection, ID: Hashable> {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    init(_ data: Data, id: KeyPath<Data.Element, ID>) {
        self.data = data; self.id = id
    }
}
'''
production = '\n'.join(declaration(source, marker) for marker in (
    'struct RoleTextFade:', 'final class RoleTextRevealTimeline {',
    'final class RoleTextRevealHistory {', 'struct RoleRevealRenderer:'))
list_body = declaration(source, 'struct RoleLiveItemsList:')
# Use the actual collection and identity key path supplied to SwiftUI.
row_expression = re.search(r'ForEach\((.*?)\) \{', list_body).group(1)
production += '''
func segmentIDs(_ segments: [String]) -> [String] {
    let identities = segments
    let rows = ForEach(''' + row_expression + ''')
    return rows.data.map { String(describing: $0[keyPath: rows.id]) }
}
'''
tests = (ROOT / 'Tests/ChatRenderStabilityTests.swift').read_text()
tests += '\n' + (ROOT / 'Tests/RoleTextRevealHistoryTests.swift').read_text().replace(
    '@testable import TaskFlow', '')
with tempfile.TemporaryDirectory(prefix='chat-render-stability-') as tmp:
    main = Path(tmp) / 'main.swift'
    main.write_text(stubs + production + '\n' + tests + '''
let suite = ChatRenderStabilityTests.defaultTestSuite
suite.run()
let existing = RoleTextRevealHistoryTests.defaultTestSuite
existing.run()
exit(suite.testRun!.hasSucceeded && existing.testRun!.hasSucceeded ? 0 : 1)
''')
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    binary = Path(tmp) / 'tests'
    subprocess.run(['swiftc', '-D', 'CHAT_RENDER_HOST', '-F', str(frameworks),
                    '-I', str(libraries), '-L', str(libraries),
                    '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                    '-Xlinker', '-rpath', '-Xlinker', str(libraries),
                    str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
