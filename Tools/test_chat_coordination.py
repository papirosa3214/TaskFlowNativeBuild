#!/usr/bin/env python3
"""Run the real chat feed filter with lightweight model fixtures on macOS.
No app, simulator or UI automation. Decoder/server integration is tested separately.
"""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Features/Chat/RoleChatsScreen.swift').read_text()
start = source.index('    private var visibleMessages: [RoleChatMessage] {')
opening = source.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
body = source[start:end].replace('private var visibleMessages', 'var visibleMessages')
fixture = '''import Foundation
import XCTest
struct RoleChatMessage { let id: String; var isFinishedCoordinationRow = false }
struct Turn { func isCompleted(by message: RoleChatMessage) -> Bool { false } }
struct Feed {
var messages: [RoleChatMessage] = []
var completingTurns: [String: Turn] = [:]
var completedMessageIDByTurn: [String: String] = [:]
'''
tests = '''
}
final class CoordinationFeedTests: XCTestCase {
 @objc func testAnsweredCardRemainsReadable() {
  XCTAssertEqual(Feed(messages: [.init(id: "answered", isFinishedCoordinationRow: true)]).visibleMessages.map(\\.id), ["answered"])
 }
 @objc func testOpenAndOrdinaryMessagesRemain() {
  XCTAssertEqual(Feed(messages: [.init(id: "open"), .init(id: "plain")]).visibleMessages.map(\\.id), ["open", "plain"])
 }
 @objc func testOnlyExactCompletingMessageIsHidden() {
  let feed = Feed(messages: [.init(id: "card", isFinishedCoordinationRow: true), .init(id: "final")], completingTurns: ["turn": Turn()], completedMessageIDByTurn: ["turn": "final"])
  XCTAssertEqual(feed.visibleMessages.map(\\.id), ["card"])
 }
}
let suite = CoordinationFeedTests.defaultTestSuite
suite.run()
exit(suite.testRun!.hasSucceeded ? 0 : 1)
'''
with tempfile.TemporaryDirectory(prefix='coordination-host-') as tmp:
    main = Path(tmp) / 'main.swift'; binary = Path(tmp) / 'tests'
    main.write_text(fixture + body + tests)
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
    libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
