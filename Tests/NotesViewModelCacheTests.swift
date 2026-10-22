import XCTest
@testable import TaskFlow

/// Кэш дерева строк «Заметок» — LOCK-OPT-PERF-20261022.
///
/// `NotesViewModel.rows` — вычисляемое свойство, его читает `ForEach` прямо
/// в теле экрана. Дерево собиралось заново на каждом проходе `body`, а внутри
/// для каждой папки заново считались счётчик заметок и «последняя заметка» —
/// с разбором дат по каждой заметке в каждой папке.
///
/// Проверяем: при неизменных данных дерево собирается ОДИН раз, при
/// изменённых — снова, и содержимое дерева не изменилось.
@MainActor
final class NotesViewModelCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NotesViewModel.rowsBuildCount = 0
    }

    private func makeNote(_ index: Int, folderId: Int?, day: Int = 1) -> NoteListItem {
        let stamp = String(format: "2026-10-%02d 12:00:00", day)
        return NoteListItem(
            id: "n\(index)",
            title: "Заметка \(index)",
            folderId: folderId,
            preview: "Текст \(index)",
            createdAt: stamp,
            updatedAt: stamp
        )
    }

    private func makeModel(notes: Int = 20, folders: Int = 5) -> NotesViewModel {
        let model = NotesViewModel()
        model.folders = (0..<folders).map { index in
            ApiJournalFolder(id: index, name: "Папка \(index)", parentId: nil)
        }
        model.notes = (0..<notes).map { index in
            makeNote(index, folderId: index % max(folders, 1), day: index % 20 + 1)
        }
        return model
    }

    // MARK: - Кэш

    func testНеизменныеДанныеНеПересобираютДерево() {
        let model = makeModel()
        _ = model.rows
        _ = model.rows
        XCTAssertEqual(
            NotesViewModel.rowsBuildCount, 1,
            "Дерево с теми же данными должно собираться один раз, а не на каждый проход экрана"
        )
    }

    func testНоваяЗаметкаПересобираетДерево() {
        let model = makeModel()
        _ = model.rows
        model.notes.append(makeNote(999, folderId: nil))
        _ = model.rows
        XCTAssertEqual(NotesViewModel.rowsBuildCount, 2, "Новая заметка обязана пересобрать дерево")
    }

    func testРаскрытиеПапкиПересобираетДерево() {
        let model = makeModel()
        model.expandedFolderIDs = [0]
        _ = model.rows
        model.toggleExpanded(0)
        _ = model.rows
        XCTAssertEqual(NotesViewModel.rowsBuildCount, 2, "Сворачивание папки обязано пересобрать дерево")
    }

    // MARK: - Содержимое не изменилось

    func testДеревоСодержитПапкиИЗаметки() {
        let model = makeModel(notes: 4, folders: 2)
        let rows = model.rows
        // Свёрнутые папки: заметки внутри не видны, строки — только папки.
        XCTAssertEqual(rows.map(\.rowID), ["f:0", "f:1"])
        XCTAssertEqual(rows.filter { if case .folder = $0.kind { return true } else { return false } }.count, 2)
        XCTAssertEqual(rows.filter { if case .note = $0.kind { return true } else { return false } }.count, 0)
    }

    func testРаскрытаяПапкаПоказываетСвоиЗаметки() {
        let model = makeModel(notes: 4, folders: 2)
        model.expandedFolderIDs = [0]
        let rows = model.rows
        // Внутри папки заметки идут по дате: сначала новые (n2 — 3 октября,
        // затем n0 — 1 октября). Идентификатор строки — «n:» + id заметки.
        XCTAssertEqual(rows.map(\.rowID), ["f:0", "n:n2", "n:n0", "f:1"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1, 0])
    }

    func testСчётчикЗаметокВПапкеНеИзменился() {
        let model = makeModel(notes: 4, folders: 2)
        let folder = model.rows.first { if case .folder = $0.kind { return true } else { return false } }
        guard case .folder(_, let noteCount, let latestNote) = folder?.kind else {
            return XCTFail("Ожидалась строка папки")
        }
        XCTAssertEqual(noteCount, 2, "В папке 0 две заметки: n0 и n2")
        XCTAssertEqual(latestNote?.id, "n2", "Последняя по дате — n2 (14 октября)")
    }
}
