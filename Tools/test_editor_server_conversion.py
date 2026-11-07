#!/usr/bin/env python3
"""Execute the real editor setters: raw drafts must not invoke MarkdownParser."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/Features/Tasks/TaskFormViewModel.swift').read_text()
def setter(property_name):
    begin=source.index('    var '+property_name+': String {')
    begin=source.index('        set {', begin)+len('        set ')
    cursor=begin+1; depth=1
    while depth:
        depth+=(source[cursor]=='{')-(source[cursor]=='}');cursor+=1
    return source[begin:cursor]
fixture='''import Foundation
enum MarkdownParser {
 static var calls=0
 static func parse(_ text: String) -> [NoteBlock] {
  calls += 1
  return [NoteBlock(kind: .paragraph, runs: [RichRun(text: text, bold: true)])]
 }
}
struct Editor {
 var titleBlocks: [NoteBlock]=[]
 var taskDescriptionBlocks: [NoteBlock]=[]
 var commentBlocks: [NoteBlock]=[]
 var cachedDescriptionMarkdown: String?
 var cachedTitleMarkdown: String?
 var cachedCommentMarkdown: String?
 mutating func title(_ newValue: String) BODY_TITLE
 mutating func description(_ newValue: String) BODY_DESCRIPTION
 mutating func comment(_ newValue: String) BODY_COMMENT
}
func check(_ condition: Bool, _ message: String) { if !condition { print("FAIL: " + message); exit(1) } }
var editor=Editor()
let input="**typed** `code` | table |"
editor.title(input); editor.description(input); editor.comment(input)
check(MarkdownParser.calls == 0, "editor must never run the local Markdown parser")
for blocks in [editor.titleBlocks,editor.taskDescriptionBlocks,editor.commentBlocks] {
 check(blocks.first?.plainText == input, "input is retained literally until server conversion")
 check(blocks.first?.runs.first?.bold == false, "formatting cannot be guessed locally")
}
check(editor.cachedDescriptionMarkdown == input, "raw description source is retained")
print("PASS: title/description/comment retain raw drafts without local parsing")
'''
for name,prop in [('TITLE','title'),('DESCRIPTION','taskDescription'),('COMMENT','commentText')]:
    fixture=fixture.replace('BODY_'+name,setter(prop))
with tempfile.TemporaryDirectory(prefix='server-editor-') as directory:
    main=Path(directory)/'main.swift'; main.write_text(fixture)
    binary=Path(directory)/'test'
    subprocess.run(['swiftc',str(root/'Sources/Core/Common/JSONValue.swift'),str(root/'Sources/Core/Models/NoteDocument.swift'),str(main),'-o',str(binary)],check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
