"""Host replay of production chat completion; no UI/simulator."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
screen = (ROOT / 'Sources/Features/Roles/RoleChatRoomScreen.swift').read_text()

def block(signature):
    start = screen.index(signature)
    end = screen.index('{', start) + 1
    depth = 1
    while depth:
        depth += (screen[end] == '{') - (screen[end] == '}')
        end += 1
    return screen[start:end]

method = block('private func completeLiveTurn(').replace('private func', 'mutating func')
snapshot_filter = screen.split('let turns = snapshot.turns.filter', 1)[1].split('let previous = liveTurns', 1)[0]
fixture = r'''
import Foundation
enum Item { case text(String) }
struct SavedSteps { let items: [Item] }
struct RoleChatMessage {
 let id: String; var hasStructuredAnswer = true; var stopReason: String? = nil
 var text = "short final"; var steps: SavedSteps? = nil
 var roleEnvelopeJSON: String? = #"{"output":[{"type":"text","text":"short final"}]}"#
}
struct RoleChatLiveTurn {
 let playbackID: String; var items: [Item] = [.text("draft")]
 var userID: String { "role" }; var triggerMessageID: String? { playbackID }
 func completed(with message: RoleChatMessage) -> Self { self }
 func itemsWithoutAnswerText(for message: RoleChatMessage) -> [Item] { items }
}
enum RoleChatRowID { static func turn(_ id: String) -> String { id } }
enum RoleChatLiveCompletion { static func shouldHoldSavedMessage(for turn: RoleChatLiveTurn) -> Bool { true } }
struct ClientLog { static let shared = ClientLog(); func add(_ text: String) {} }
struct Chat { let id = "chat" }
struct State {
 let chat = Chat()
 var rowIDByMessageID: [String: String] = [:]
 var closedTurnMessageIDs: Set<String> = []
 var closedTurnItems: [String: [Item]] = [:]
 var endedTurnIDs: Set<String> = []
 var stoppedTurnIDs: Set<String> = []
 var completingTurns: [String: RoleChatLiveTurn] = [:]
 var completedMessageIDByTurn: [String: String] = [:]
''' + method + r'''
}
let turn = RoleChatLiveTurn(playbackID: "role:turn")
let message = RoleChatMessage(id: "answer")
for endedFirst in [false, true] {
 for alreadyShown in [false, true] {
  var state = State()
  if endedFirst { state.endedTurnIDs.insert(turn.playbackID) }
  state.completingTurns[turn.playbackID] = turn
  state.completeLiveTurn(turn, with: message, alreadyShown: alreadyShown)
  precondition(state.completingTurns.isEmpty, "saved reply still hidden behind live playback")
  precondition(state.endedTurnIDs.contains(turn.playbackID), "late snapshot can resurrect finished turn")
  state.completeLiveTurn(turn, with: message, alreadyShown: true)
  precondition(state.completingTurns.isEmpty, "repeated completion replays reply")
 }
}
print("PASS: saved reply immediately visible, end ordering and repeats stable")
struct Snapshot { let turns: [RoleChatLiveTurn] }
let endedTurnIDs: Set<String> = ["ended"]
func hasAnswer(on trigger: String, from userID: String) -> Bool { trigger == "answered" }
let snapshot = Snapshot(turns: ["ended", "answered", "new"].map { RoleChatLiveTurn(playbackID: $0) })
let turns = snapshot.turns.filter
''' + snapshot_filter + r'''
precondition(turns.map(\.playbackID) == ["new"], "snapshot resurrected ended or answered work")
print("PASS: REST snapshot rejects ended and answered turns")
'''
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    main.write_text(fixture)
    subprocess.run(['swiftc', str(main), '-o', directory + '/test'], check=True)
    result = subprocess.run([directory + '/test'], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('FAIL: completion/snapshot/answer presentation regression')
    print(result.stdout.strip())

for signature in ['private func flatReplyRow(', 'private func messageBubbleRow(']:
    assert 'RoleLiveItemsList' not in block(signature), 'finished chat reply renders work history'
assert 'RoleLiveTurnBubble' in (ROOT / 'Sources/Features/Tasks/Detail/TaskLiveActivityView.swift').read_text()
content = block('private func roleMessageContent(')
assert 'text: message.text' in content and 'serverBlocks: message.blocks' in content
print('PASS: finished chat has no work history; task activity keeps its renderer')
