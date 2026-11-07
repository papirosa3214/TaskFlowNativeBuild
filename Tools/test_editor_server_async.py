#!/usr/bin/env python3
"""Run real async editor methods with a controlled network response on macOS."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/Features/Tasks/TaskFormViewModel.swift').read_text()
def method(signature, source=source):
    start=source.index(signature); cursor=source.index('{',start)+1; depth=1
    while depth:
        depth+=(source[cursor]=='{')-(source[cursor]=='}');cursor+=1
    return source[start:cursor].replace('private func ', 'func ')+'\n'
encoder=(root/'Sources/Core/Text/MarkdownParser.swift').read_text()
encoder=encoder[encoder.index('enum MarkdownEncoder {'):]
fixture='''import Foundation
struct ApiSubtask { let title: String }
enum TaskPriority: Int { case high = 2, low = 4 }
enum TaskDay { static func date(from value: String?) -> Date? { nil } }
typealias APIClient = FakeAPI
@MainActor final class FakeAPI {
 struct StructuredTask { let title: String; let description: String?; let subtasks: [String]; let dueDate: String?; let priority: Int? }
 func createSubtask(taskId: String, title: String) async throws -> ApiSubtask { ApiSubtask(title: title) }
 var pending: [CheckedContinuation<JSONValue, Error>] = []
 var requests: [String] = []
 enum Method { case post }
 func request<T: Decodable>(_ method: Method, _ path: String, body: [String: JSONValue]) async throws -> T {
  check(method == .post && path == "/notes/markdown-to-doc", "existing conversion endpoint and POST")
  requests.append(body["markdown"]?.stringValue ?? "")
  let doc: JSONValue = try await withCheckedThrowingContinuation { pending.append($0) }
  return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(JSONValue.object(["doc": doc])))
 }
 API_METHOD
 func finish(_ result: Result<JSONValue, Error>) { pending.removeFirst().resume(with: result) }
}
@MainActor final class Editor {
 let apiClient = FakeAPI()
 var taskID: String?
 var dueDate: Date?
 var priority: TaskPriority = .low
 var subtaskDrafts: [SubtaskDraft] = []
 var subtasks: [ApiSubtask] = []
 var saveErrorMessage: String?
 var cachedTitleMarkdown: String?
 var cachedDescriptionMarkdown: String?
 var cachedCommentMarkdown: String?
 var titleBlocks: [NoteBlock] = [] { didSet { cachedTitleMarkdown = nil } }
 var taskDescriptionBlocks: [NoteBlock] = [] { didSet { cachedDescriptionMarkdown = nil } }
 var commentBlocks: [NoteBlock] = [] { didSet { cachedCommentMarkdown = nil } }
 var title: String {
  get { cachedTitleMarkdown ?? MarkdownEncoder.encode(titleBlocks) }
  set { titleBlocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: newValue)])]; cachedTitleMarkdown = newValue }
 }
 var taskDescription: String {
  get { cachedDescriptionMarkdown ?? MarkdownEncoder.encode(taskDescriptionBlocks) }
  set { taskDescriptionBlocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: newValue)])]; cachedDescriptionMarkdown = newValue }
 }
 var commentText: String {
  get { cachedCommentMarkdown ?? MarkdownEncoder.encode(commentBlocks) }
  set { commentBlocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: newValue)])]; cachedCommentMarkdown = newValue }
 }
'''
api=(root/'Sources/Core/Networking/APIClient+Notes.swift').read_text()
fixture=fixture.replace('API_METHOD', method('    func markdownDocument(', api))
for name in ['editorBlocks','setTitleFromMarkdown','setDescriptionFromMarkdown','setCommentFromMarkdown']:
    fixture+=method('    func '+name+'(')
fixture+=method('    private func apply(')
fixture+=method('    private func normalizedSubtaskTitle(')
draft_source=(root/'Sources/Features/Tasks/Fields/SubtaskFormFieldView.swift').read_text()
draft_source=draft_source[draft_source.index('struct SubtaskDraft:'):draft_source.index('/// `AddSubtaskRow`')]
fixture=draft_source+'\n'+fixture
fixture+='''}
func check(_ value: Bool, _ message: String) { if !value { print("FAIL: " + message); exit(1) } }
@main struct Tests {
 @MainActor static func main() async throws {
  let vm = Editor()
  let doc: JSONValue = .object(["type": .string("doc"), "content": .array([
   .object(["type": .string("paragraph"), "content": .array([
    .object(["type": .string("text"), "text": .string("server"), "marks": .array([.object(["type": .string("bold")])])])
   ])])
  ])])
  let first = Task { await vm.setTitleFromMarkdown("**first**") }
  while vm.apiClient.pending.isEmpty { await Task.yield() }
  check(vm.title == "**first**", "raw draft exists while server is pending")
  vm.titleBlocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: "owner new text")])]
  vm.apiClient.finish(.success(doc)); await first.value
  check(vm.titleBlocks.first?.plainText == "owner new text", "late title response cannot overwrite input")
  let second = Task { await vm.setTitleFromMarkdown("**second**") }
  while vm.apiClient.pending.isEmpty { await Task.yield() }
  vm.apiClient.finish(.success(doc)); await second.value
  check(vm.titleBlocks.first?.runs.first?.bold == true, "formatting comes from server")
  check(vm.title == "**second**", "server conversion retains exact raw source")
  let failing = Task { await vm.setDescriptionFromMarkdown("**offline draft**") }
  while vm.apiClient.pending.isEmpty { await Task.yield() }
  vm.apiClient.finish(.failure(URLError(.notConnectedToInternet))); await failing.value
  check(vm.taskDescription == "**offline draft**", "network failure retains description")
  check(vm.saveErrorMessage != nil, "conversion failure is reported")
  let comment = Task { await vm.setCommentFromMarkdown("**comment**") }
  while vm.apiClient.pending.isEmpty { await Task.yield() }
  vm.commentBlocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: "new comment")])]
  vm.apiClient.finish(.success(doc)); await comment.value
  check(vm.commentBlocks.first?.plainText == "new comment", "late comment response cannot overwrite input")
  check(vm.apiClient.requests == ["**first**", "**second**", "**offline draft**", "**comment**"], "exact drafts sent to server")
  let imported = try NoteDocument.fromServer(doc).blocks
  var localDraft = SubtaskDraft(title: "**step**", blocks: imported)
  let draftID = localDraft.id
  check(localDraft.blocks.first?.runs.first?.bold == true, "new step preserves server marks")
  localDraft.title = "owner draft"
  check(localDraft.id == draftID && localDraft.blocks.first?.plainText == "owner draft", "plain draft edit keeps identity and text")
  let ai = Editor(); ai.title = "original"; ai.taskDescription = "original description"
  let structured = FakeAPI.StructuredTask(title: "new", description: "description", subtasks: ["step"], dueDate: nil, priority: 2)
  let aiFailure = Task { do { try await ai.apply(structured); return false } catch { return true } }
  while ai.apiClient.pending.isEmpty { await Task.yield() }
  ai.apiClient.finish(.success(doc))
  while ai.apiClient.pending.isEmpty { await Task.yield() }
  check(ai.title == "original", "AI waits for all field conversions before applying")
  ai.apiClient.finish(.failure(URLError(.notConnectedToInternet)))
  let failed = await aiFailure.value
  check(failed && ai.title == "original" && ai.taskDescription == "original description", "failed AI conversion preserves all original fields")
  let success = Task { try await ai.apply(structured) }
  for _ in 0..<3 {
   while ai.apiClient.pending.isEmpty { await Task.yield() }
   ai.apiClient.finish(.success(doc))
  }
  try await success.value
  check(ai.title == "new" && ai.taskDescription == "description" && ai.subtaskDrafts.map(\.title) == ["step"], "AI applies all prepared fields")
  check(ai.subtaskDrafts.first?.blocks.first?.runs.first?.bold == true, "AI step uses server document")
  print("PASS: real async editor/API: server marks, late replies, network failure, raw drafts, atomic AI import")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='server-editor-async-') as directory:
    main=Path(directory)/'main.swift';main.write_text(encoder+'\n'+fixture)
    binary=Path(directory)/'test'
    subprocess.run(['swiftc','-parse-as-library',str(root/'Sources/Core/Common/JSONValue.swift'),str(root/'Sources/Core/Models/NoteDocument.swift'),str(main),'-o',str(binary)],check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
