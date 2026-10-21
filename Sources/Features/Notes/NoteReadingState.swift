import Foundation

struct NoteReadingState {
    private(set) var markdown = ""
    var draft = ""
    private(set) var isEditing = false

    var hasChanges: Bool { draft != markdown }

    mutating func load(_ text: String) {
        markdown = text
        draft = text
        isEditing = false
    }

    mutating func beginEditing() {
        draft = markdown
        isEditing = true
    }

    mutating func didSave(_ snapshot: String) {
        markdown = snapshot
    }

    @discardableResult
    mutating func finishEditing() -> Bool {
        guard !hasChanges else { return false }
        isEditing = false
        return true
    }
}
