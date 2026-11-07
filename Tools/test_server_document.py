#!/usr/bin/env python3
"""Decode real server TipTap values on macOS; no UI/simulator."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
call = 'try NoteDocument.fromServer(value)'
fixture = r'''import Foundation
func decode(_ value: JSONValue?) throws -> NoteDocument { CALL }
func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL: " + message); exit(1) } }
let json = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"**literal**","marks":[{"type":"bold"}]}]}]}"#
let document = try decode(.string(json))
check(document.blocks.first?.plainText == "**literal**", "server text is literal, not Markdown")
check(document.blocks.first?.runs.first?.bold == true, "server marks preserved")
var rejected = false
do { _ = try decode(.string("**raw Markdown**")) } catch { rejected = true }
check(rejected, "raw Markdown must be rejected, not parsed or replaced by an empty document")
rejected = false
do { _ = try decode(nil) } catch { rejected = true }
check(rejected, "missing server document must be rejected")
let object = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
let objectDocument = try decode(object)
check(objectDocument.blocks.first?.plainText == "**literal**", "JSON object is accepted")
let serverBlocks = try JSONDecoder().decode([ChatServerBlock].self, from: Data(#"[{"type":"doc","chars":11,"doc":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"**literal**"}]}]}},{"type":"table","header":[[{"type":"text","text":"A"}]],"rows":[[[{"type":"text","text":"**cell**","marks":[{"type":"bold"}]}]]]}]"#.utf8))
let segments = ChatRichContent.segmentsUncached(fromServer: serverBlocks)
guard case .document(let blocks, _) = segments.first, case .table(let table) = segments.last else { fatalError("server blocks missing") }
check(blocks.first?.plainText == "**literal**", "document must not parse Markdown")
check(blocks.first?.runs.first?.bold == false, "marks must come from server only")
check(table.rowRuns?[0][0].first?.text == "**cell**", "table text must stay literal")
check(table.rowRuns?[0][0].first?.bold == true, "table marks must come from server")
print("PASS: server documents and tables; literal text, marks, object/string, missing and malformed data")
'''.replace('CALL', call)
# Exercise the real task adoption/comparison methods with server-prepared documents.
vm = (root / 'Sources/Features/Tasks/TaskFormViewModel.swift').read_text()
def method(signature):
    start = vm.index(signature); cursor = vm.index('{', start) + 1; depth = 1
    while depth:
        depth += (vm[cursor] == '{') - (vm[cursor] == '}'); cursor += 1
    return vm[start:cursor].replace('private func ', 'mutating func ') + '\n'
encoder = (root / 'Sources/Core/Text/MarkdownParser.swift').read_text()
encoder = encoder[encoder.index('enum MarkdownEncoder {'):]
fixture += encoder + """
struct ApiTask { var title: String = "server title"; var titleDocument: JSONValue?; var descriptionDocument: JSONValue?; var description: String? }
struct Form {
 var titleBlocks: [NoteBlock] = []
 var cachedTitleMarkdown: String?
 var taskDescriptionBlocks: [NoteBlock] = [] { didSet { cachedDescriptionMarkdown = nil } }
 var cachedDescriptionMarkdown: String?
 var originalTask: ApiTask?
 var taskDescription: String { cachedDescriptionMarkdown ?? MarkdownEncoder.encode(taskDescriptionBlocks) }
""" + method('    private func adoptTitleDocument(') + method('    private func adoptDescriptionDocument(') + method('    func descriptionMatches(') + """
}
var form = Form()
let task = ApiTask(titleDocument: object, descriptionDocument: object, description: "server source")
form.originalTask = task
try form.adoptTitleDocument(from: task)
try form.adoptDescriptionDocument(from: task)
check(form.taskDescription == "server source", "adoption preserves exact source, no phantom edit")
check(form.descriptionMatches(task.description), "unchanged description matches server")
let unchangedBlocks = form.taskDescriptionBlocks
form.taskDescriptionBlocks = unchangedBlocks
check(form.descriptionMatches(task.description), "editor rebinding is not a user edit")
form.taskDescriptionBlocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: "owner edit")])]
check(!form.descriptionMatches(task.description), "owner edit cannot be overwritten by polling")
print("PASS: task adoption preserves source and server marks; rebinding and owner edits stay distinct")
"""
with tempfile.TemporaryDirectory(prefix='server-document-') as directory:
    main = Path(directory) / 'main.swift'; main.write_text(fixture)
    binary = Path(directory) / 'test'
    subprocess.run(['swiftc', str(root/'Sources/Core/Common/JSONValue.swift'), str(root/'Sources/Core/Models/NoteDocument.swift'), str(root/'Sources/Core/Models/ChatServerBlock.swift'), str(root/'Sources/Core/Models/AgentComponent.swift'), str(root/'Sources/Core/Common/ParsedValueCache.swift'), str(root/'Sources/Chat/Feed/ChatRichContent.swift'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
