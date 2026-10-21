import XCTest
@testable import TaskFlow

final class NoteReadingStateTests: XCTestCase {
    func testLoadedNoteStartsInReadingWithoutPendingSave() {
        var state = NoteReadingState()
        state.load("# Документ\n\n| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertFalse(state.isEditing)
        XCTAssertFalse(state.hasChanges)
        XCTAssertEqual(state.markdown, state.draft)
    }

    func testUnchangedEditingReturnsToReadingWithoutSave() {
        var state = NoteReadingState()
        state.load("# Текст")
        state.beginEditing()
        XCTAssertTrue(state.isEditing)
        XCTAssertTrue(state.finishEditing())
        XCTAssertFalse(state.hasChanges)
        XCTAssertFalse(state.isEditing)
    }

    func testChangedDraftRequiresSuccessfulSaveBeforeReading() {
        var state = NoteReadingState()
        state.load("До")
        state.beginEditing()
        state.draft = "После"
        XCTAssertFalse(state.finishEditing())
        XCTAssertTrue(state.isEditing)
        state.didSave("После")
        XCTAssertTrue(state.finishEditing())
        XCTAssertEqual(state.markdown, "После")
    }

    func testSavingOlderSnapshotKeepsNewerDraftDirty() {
        var state = NoteReadingState()
        state.load("До")
        state.beginEditing()
        state.draft = "Первое изменение"
        let snapshot = state.draft
        state.draft = "Второе изменение"
        state.didSave(snapshot)
        XCTAssertTrue(state.hasChanges)
        XCTAssertEqual(state.draft, "Второе изменение")
        XCTAssertFalse(state.finishEditing())
    }
}
