#!/usr/bin/env python3
"""Host behavior checks for source-edit commands and the real run-font selection."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
reply=(root/'Sources/Chat/Output/RoleReplyMarkdown.swift').read_text()
a=reply.index('    private static func readableText(');end=reply.index('    /// Готовый кусок',a)
method=reply[a:end].replace('private static func','static func')
base='baseFont:' in method
fixture='''import Foundation
struct Color { func opacity(_ value: Double) -> Color { self } }
struct Font {
 enum Weight { case bold }
 enum Group: String { case body, emphasis, mono }
 enum Design { case monospaced }
 let name: String
 static func tfChat(_ group: Group, weight: Weight? = nil, design: Design? = nil) -> Font { Font(name: group.rawValue) }
 func monospaced() -> Font { Font(name: name + "-mono") }
}
struct Text {
 static var fonts: [String] = []
 init(_ value: String) {}
 init(_ value: AttributedString) {}
 func font(_ value: Font) -> Text { Self.fonts.append(value.name); return self }
 func fontWeight(_ value: Font.Weight?) -> Text { self }
 func foregroundColor(_ color: Color) -> Text { self }
}
struct Renderer {
 struct RunPiece { var attributed = AttributedString("word"); var bold = false; var code = false }
METHOD
 static func test() {
  Text.fonts=[]
  _ = readableText([RunPiece()], color: Color(), liftBold: falseBASE)
  guard Text.fonts == ["heading"] else { print("FAIL: heading overridden by body font:",Text.fonts);exit(1) }
  Text.fonts=[]
  _ = readableText([RunPiece(bold: true)],color: Color())
  guard Text.fonts == ["emphasis"] else { print("FAIL: body bold changed");exit(1) }
  Text.fonts=[]
  _ = readableText([RunPiece(code: true)],color: Color())
  guard Text.fonts == ["mono"] else { print("FAIL: inline code changed");exit(1) }
 }
}
Renderer.test()
print("PASS: real renderer preserves heading font, ordinary emphasis and code")
'''.replace('METHOD',method).replace('BASE',', baseFont: Font(name: "heading")' if base else '')
source=(root/'Sources/DesignSystem/Components/TFMarkdownSourceEditor.swift').read_text()
if 'enum MarkdownSourceCommands {' in source:
    commands=source[source.index('enum MarkdownSourceCommands {'):]
    fixture+='\n'+commands+'''
func check(_ condition: Bool,_ message: String) { if !condition { print("FAIL: " + message);exit(1) } }
let bold=MarkdownSourceCommands.wrap("hello",range:NSRange(location:0,length:5),open:"**",close:"**")
check(bold.text == "**hello**" && bold.selection == NSRange(location:2,length:5),"wrap selected text")
let plain=MarkdownSourceCommands.wrap(bold.text,range:bold.selection,open:"**",close:"**")
check(plain.text == "hello" && plain.selection == NSRange(location:0,length:5),"toggle wrap off")
let empty=MarkdownSourceCommands.wrap("ab",range:NSRange(location:1,length:0),open:"`",close:"`")
check(empty.text == "a``b" && empty.selection.location == 2,"empty selection leaves cursor inside code")
let unicode=MarkdownSourceCommands.wrap("😀 Привет",range:NSRange(location:3,length:6),open:"**",close:"**")
check(unicode.text == "😀 **Привет**","UTF16 selection preserves emoji")
let heading=MarkdownSourceCommands.prefix("Intro\\nTitle\\nTail",range:NSRange(location:8,length:0),marker:"## ")
check(heading.text == "Intro\\n## Title\\nTail","heading prefix starts at line boundary")
let removed=MarkdownSourceCommands.prefix(heading.text,range:heading.selection,marker:"## ")
check(removed.text == "Intro\\nTitle\\nTail","heading toggles off")
let code=MarkdownSourceCommands.codeBlock("before\\ncode\\nafter",range:NSRange(location:7,length:4))
check(code.text == "before\\n```\\ncode\\n```\\nafter","code fences occupy separate lines")
let both=MarkdownSourceCommands.wrap(bold.text,range:bold.selection,open:"*",close:"*")
check(both.text == "***hello***","italic preserves existing bold")
let onlyBold=MarkdownSourceCommands.wrap(both.text,range:both.selection,open:"*",close:"*")
check(onlyBold.text == "**hello**","turning italic off preserves bold")
let link=MarkdownSourceCommands.link("label",range:NSRange(location:0,length:5))
check(link.text == "[label](https://)" && (link.text as NSString).substring(with:link.selection) == "https://","link selects editable URL")
let emptyLink=MarkdownSourceCommands.link("",range:NSRange(location:0,length:0))
check(emptyLink.text == "[Ссылка](https://)" && (emptyLink.text as NSString).substring(with:emptyLink.selection) == "https://","empty link gets an editable label and URL")
let unlinked=MarkdownSourceCommands.link(link.text,range:NSRange(location:1,length:5))
check(unlinked.text == "label" && unlinked.selection == NSRange(location:0,length:5),"link toggle selection stays valid")
let uncode=MarkdownSourceCommands.codeBlock(code.text,range:code.selection)
check(uncode.text == "before\\ncode\\nafter","code block toggle preserves surrounding paragraphs")
print("PASS: source commands: selection, toggle, Unicode, headings, code, links and combined marks")
'''
with tempfile.TemporaryDirectory(prefix='note-formatting-') as directory:
    main=Path(directory)/'main.swift';main.write_text(fixture)
    binary=Path(directory)/'test'
    built = subprocess.run(['swiftc',str(main),'-o',str(binary)],capture_output=True,text=True)
    if built.returncode:
        print('\n'.join(built.stderr.splitlines()[:18]));raise SystemExit(built.returncode)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
