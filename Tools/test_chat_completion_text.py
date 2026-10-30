#!/usr/bin/env python3
"""Run the actual completion merger on macOS with minimal value fixtures."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/Core/Models/RoleChat.swift').read_text()
a=s.index('    func completed(with message: RoleChatMessage) -> Self'); b=s.index('{',a); end=b+1; depth=1
while depth:
    depth+=(s[end]=='{')-(s[end]=='}');end+=1
method=s[a:end]
source='''import Foundation
struct Action { let id: String }
enum RoleChatLiveItem { case text(String), step(Action), thinking(Action) }
struct Steps { let items: [RoleChatLiveItem] }
struct RoleChatMessage { let text: String; let steps: Steps? }
struct Turn {
 let chatID: String; let userID: String; let name: String; let startedAt: String?
 let items: [RoleChatLiveItem]; let thinking: String?; let triggerMessageID: String?
'''+method+'''
}
let full = "Да, читал. Как роли находят проекты. Как собирается сервер."
let turn = Turn(chatID: "c", userID: "r", name: "R", startedAt: nil,
 items: [.step(Action(id: "a")), .text("Да, читал. Как рол"), .text("Как с"), .text("Как")],
 thinking: nil, triggerMessageID: nil)
let message = RoleChatMessage(text: full, steps: Steps(items: [.step(Action(id: "a")), .text(full)]))
let result = turn.completed(with: message)
let texts = result.items.compactMap { if case .text(let t) = $0 { return t }; return nil }
let actions = result.items.compactMap { if case .step(let a) = $0 { return a.id }; return nil }
guard texts == [full], actions == ["a"] else { print("FAIL: duplicate text snapshots:", texts); exit(1) }
let again = result.completed(with: message)
let againTexts = again.items.compactMap { if case .text(let t) = $0 { return t }; return nil }
guard againTexts == [full] else { print("FAIL: repeated completion duplicates text"); exit(1) }
print("PASS: partial snapshots replaced, actions retained, repeated completion stable")
'''
with tempfile.TemporaryDirectory(prefix='chat-completion-') as d:
 p=Path(d);(p/'main.swift').write_text(source)
 subprocess.run(['swiftc',str(p/'main.swift'),'-o',str(p/'run')],check=True)
 raise SystemExit(subprocess.run([str(p/'run')]).returncode)
