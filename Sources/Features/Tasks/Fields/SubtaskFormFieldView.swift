import SwiftUI

// Подзадачи формы — spec/SCREENS-1.md §3.7/§5.5.
//
// Два режима были реализованы отдельными view (`SubtaskDraftListView` — create,
// `SubtaskEditListView` — edit). Оба архивированы 2026-09-11 в
// archive/task-fields-2026-09-11/ по DEAD-CODE-CLEANUP-REPORT.md; текущая форма
// работает только с моделью `SubtaskDraft`.

struct SubtaskDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String {
        didSet {
            if title != MarkdownEncoder.encode(blocks) {
                blocks = [NoteBlock(kind: .paragraph, runs: [RichRun(text: title)])]
            }
        }
    }
    var blocks: [NoteBlock]

    init(title: String, blocks: [NoteBlock]? = nil) {
        self.title = title
        self.blocks = blocks ?? [NoteBlock(kind: .paragraph, runs: [RichRun(text: title)])]
    }
}

