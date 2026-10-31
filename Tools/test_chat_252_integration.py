#!/usr/bin/env python3
"""macOS tests of production feed ordering, decoder, hints and role loading.

SwiftUI dependencies of the extracted feed are small value fixtures. The feed
method, row IDs, message decoder and loadRoles body come from production source.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]


def read(name):
    if '--index' in sys.argv:
        return subprocess.check_output(['git', 'show', ':' + name], cwd=root, text=True)
    return (root / name).read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


screen = read('Sources/Features/Roles/RoleChatsScreen.swift')
model = read('Sources/Core/Models/RoleChat.swift')
source = 'import Foundation\nimport XCTest\n'
for name in ['Sources/Core/Common/JSONValue.swift', 'Sources/Core/Models/ChatMessageInterruption.swift',
             'Sources/Core/Models/ChatMessageDeliveryState.swift', 'Sources/Core/Models/ChatExecutionMode.swift',
             'Sources/Core/Models/ChatComposerControls.swift']:
    source += read(name) + '\n'
# Fields outside the scope of these decoder tests are absent from the JSON.
source += '''
public struct ApiChatAttachment: Decodable, Sendable, Equatable {}
public struct RoleChatSteps: Decodable, Sendable {}
public struct RoleChatReaction: Decodable, Sendable {}
public struct ChecklistItemState: Decodable, Sendable {}
public struct RoleChatHandoff: Decodable, Sendable {}
public struct RoleChatCoordination: Decodable, Sendable { var isAnswered: Bool { false } }
public struct ChatServerBlock: Decodable, Sendable {}
public struct ChatQuestion: Decodable, Sendable {}
'''
source += block(model, 'public struct RoleChatMessage:') + '\n'
source += block(model, 'enum RoleChatRowID {') + '\n'
if 'public struct RoleChatPartialFlag:' in model:
    source += block(model, 'public struct RoleChatPartialFlag:') + '\n'
source += '''
struct RoleChatLiveTurn {
    let playbackID: String
    let triggerMessageID: String?
    let startedAt: String?
    var startDate: Date? { RoleChatTime.date(startedAt) }
}
enum RoleChatTime {
    static func date(_ value: String?) -> Date? { value.flatMap { ISO8601DateFormatter().date(from: $0) } }
}
struct Feed {
    var visibleMessages: [RoleChatMessage] = []
    var visibleLiveTurns: [RoleChatLiveTurn] = []
    var messages: [RoleChatMessage] { visibleMessages }
    var rowIDByMessageID: [String: String] = [:]
    var pendingOutgoing: [PendingOutgoing] = []
'''
for marker in ['private struct FeedItem:', 'private var feedItems:',
               'private func feedItemID(for message:', 'private func feedItemID(for turn:',
               'private struct PendingOutgoing:', 'private func feedAnchor(for message:']:
    source += block(screen, marker).replace('private ', '') + '\n'
source += '''
}
final class FeedIntegrationTests: XCTestCase {
    func message(_ id: String, date: String) -> RoleChatMessage {
        try! JSONDecoder().decode(RoleChatMessage.self, from: Data("{\\"id\\":\\"\\(id)\\",\\"text\\":\\"hello\\",\\"created_at\\":\\"\\(date)\\",\\"is_session_marker\\":false}".utf8))
    }
    @objc func testLiveTurnUsesAnchorWhenClockDisagrees() {
        let feed = Feed(visibleMessages: [message("q1", date: "2026-10-26T10:00:00Z"), message("q2", date: "2026-10-26T10:10:00Z")], visibleLiveTurns: [.init(playbackID: "t", triggerMessageID: "q2", startedAt: "2026-10-26T10:05:00Z")])
        XCTAssertEqual(feed.feedItems.map(\\.id), ["msg:q1", "msg:q2", "turn:t"])
    }
    @objc func testUnknownAnchorGoesToTail() {
        let feed = Feed(visibleMessages: [message("q", date: "2026-10-26T10:10:00Z")], visibleLiveTurns: [.init(playbackID: "t", triggerMessageID: "missing", startedAt: "2026-10-26T10:00:00Z")])
        XCTAssertEqual(feed.feedItems.map(\\.id), ["msg:q", "turn:t"])
    }
    @objc func testSavedFinalKeepsLiveRowIdentity() {
        let feed = Feed(visibleMessages: [message("final", date: "2026-10-26T10:10:00Z")], rowIDByMessageID: ["final": "turn:t"])
        XCTAssertEqual(feed.feedItems.map(\\.id), ["turn:t"])
    }
}
'''
suites = ['FeedIntegrationTests', 'ChatInterruptedReplyTests']
for model_name, test_name in [('ChatTimelineProjection', 'ChatTimelineProjectionTests'),
                              ('RoleChatDiscussion', 'RoleChatDiscussionTests')]:
    path = root / f'Sources/Core/Models/{model_name}.swift'
    if path.exists():
        source += read(f'Sources/Core/Models/{model_name}.swift') + '\n'
        suites.append(test_name)
for suite in suites[1:]:
    source += read(f'Tests/{suite}.swift').replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test') + '\n'
# Run the actual scenario registry and hint engine, no view overlay.
for name in ['HintModels', 'HintScenarios', 'HintCenter']:
    source += read(f'Sources/DesignSystem/Hints/{name}.swift') + '\n'
source += '''
struct RoleProfile { let canJoinChat: Bool }
enum LoadError: Error { case failed }
struct RoleAPI {
    var fails = false
    func rolesList(all: Bool = false) async throws -> [RoleProfile] {
        if fails { throw LoadError.failed }
        return []
    }
}
final class Loader {
    var roles: [RoleProfile] = []
    var isLoadingRoles = true
    var errorMessage: String?
    var api = RoleAPI()
'''
source += block(screen, 'private func loadRoles() async').replace('private ', '')
source += '\n}\n'
details = screen[screen.index('private struct RoleChatDetailsSheet:'):]
source += '''
final class DetailsLoader {
    var roles: [RoleProfile] = []
    var isLoadingRoles = true
    var errorMessage: String?
    var api = RoleAPI()
    func loadRoles() async
'''
source += block(details, '.task {').removeprefix('.task ') + '\n}\n'
if (root / 'Sources/Core/Models/RoleChatDiscussion.swift').exists():
    source += '''
struct DiscussionChat { var id: String; var taskID: String? }
struct DiscussionAPI {
    var snapshot: [RoleChatDiscussion] = []
    var fails = false
    var onLoad: (() -> Void)?
    func taskDiscussions(taskID: String) async throws -> [RoleChatDiscussion] {
        onLoad?()
        await Task.yield()
        if fails { throw LoadError.failed }
        return snapshot
    }
}
final class DiscussionLoader {
    var chat = DiscussionChat(id: "c1", taskID: "t1")
    var discussionStatus: RoleChatDiscussion?
    var api = DiscussionAPI()
'''
    source += block(screen, 'private func loadDiscussionStatus() async').replace('private ', '')
    source += '\n}\n'
source += 'var failed = false\n'
for suite in suites:
    source += f'let suite{suite} = {suite}.defaultTestSuite\nsuite{suite}.run()\nfailed = failed || !suite{suite}.testRun!.hasSucceeded\n'
source += '''
Task { @MainActor in
    var failures = failed ? 1 : 0
    for throwsError in [false, true] {
        let loader = Loader()
        loader.api.fails = throwsError
        await loader.loadRoles()
        if loader.isLoadingRoles {
            print("FAIL: role loading remains active after completion, error=\\(throwsError)")
            failures += 1
        }
        if throwsError && loader.errorMessage == nil { failures += 1 }
        let details = DetailsLoader()
        details.api.fails = throwsError
        await details.loadRoles()
        if details.isLoadingRoles { failures += 1 }
        if throwsError && details.errorMessage == nil { failures += 1 }
    }
    let defaults = UserDefaults(suiteName: "chat252-test-" + UUID().uuidString)!
    if let scenario = HintScenarios.all.first(where: { $0.id == "chat-discussion-delivery" }) {
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        if center.currentStep?.anchor != "chat.discussion-delivery" { failures += 1 }
        center.next()
        if !center.completed.contains(scenario.id) { failures += 1 }
    } else {
        print("FAIL: discussion delivery hint is missing")
        failures += 1
    }
'''
if (root / 'Sources/Core/Models/RoleChatDiscussion.swift').exists():
    source += '''
    let discussion = try! JSONDecoder().decode(RoleChatDiscussion.self, from: Data(#"{"discussion_id":"d1","chat_id":"c1","task_id":"t1","subtask_id":"s1","state":"closed","delivery_state":"awaiting","messages":2}"#.utf8))
    let loader = DiscussionLoader()
    loader.api.snapshot = [discussion]
    await loader.loadDiscussionStatus()
    if loader.discussionStatus?.discussionID != "d1" { failures += 1 }
    loader.chat.id = "another"
    await loader.loadDiscussionStatus()
    if loader.discussionStatus != nil { failures += 1 }
    loader.chat.id = "c1"
    loader.discussionStatus = discussion
    loader.chat.taskID = nil
    await loader.loadDiscussionStatus()
    if loader.discussionStatus != nil { failures += 1 }
    loader.chat.taskID = "t1"
    loader.discussionStatus = discussion
    loader.api.fails = true
    await loader.loadDiscussionStatus()
    if loader.discussionStatus != nil { failures += 1 }
    loader.api.fails = false
    loader.api.snapshot = [discussion]
    loader.api.onLoad = { loader.chat.id = "another" }
    await loader.loadDiscussionStatus()
    if loader.discussionStatus != nil { failures += 1 }
    loader.api.onLoad = nil
    loader.chat.id = "c1"
    loader.api.snapshot = []
    loader.discussionStatus = discussion
    let cancelled = Task { @MainActor in await loader.loadDiscussionStatus() }
    cancelled.cancel()
    await cancelled.value
    if loader.discussionStatus != discussion { failures += 1 }
'''
source += '''
    print("Async role-loading, discussion and hint checks: " + (failures == 0 ? "PASS" : "FAIL"))
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
'''
developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='chat252-host-') as folder:
    main = Path(folder) / 'main.swift'
    main.write_text(source)
    binary = Path(folder) / 'tests'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
                    '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath',
                    '-Xlinker', str(libraries), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
