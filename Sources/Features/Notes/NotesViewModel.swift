import Foundation
import Observation

// Вью-модель экрана «Дневник» — spec/SCREENS-2.md §1. Своя `APIClient()`
// (не из окружения) — тот же паттерн, что у `TaskFormViewModel`/
// `TodayViewModel` (Core их не раздаёт через `.environment`).
@MainActor
@Observable
final class NotesViewModel {
    private let apiClient = APIClient()

    var folders: [ApiJournalFolder] = []
    var notes: [NoteListItem] = []
    var expandedFolderIDs: Set<Int> = []
    var noteDateOrder: NotesDateOrder = .newestFirst

    var isLoading = false
    var foldersErrorMessage: String?
    var notesErrorMessage: String?
    /// Общая ошибка «прочих операций» (перемещение/переименование/удаление) — spec.
    var actionErrorMessage: String?

    // Инлайн-форма «Создать папку» — прямо в списке, без отдельного экрана.
    var isCreatingFolder = false
    var newFolderName = ""
    var isSavingFolder = false

    // Режим выбора.
    var isSelecting = false
    var selectedFolderIDs: Set<Int> = []
    var selectedNoteIDs: Set<String> = []

    var isExporting = false

    var hasAnyContent: Bool { !folders.isEmpty || !notes.isEmpty }
    var hasSelection: Bool { !selectedFolderIDs.isEmpty || !selectedNoteIDs.isEmpty }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let foldersTask: Void = loadFolders()
        async let notesTask: Void = loadNotes()
        _ = await (foldersTask, notesTask)
    }

    func loadFolders() async {
        do {
            folders = try await apiClient.journalFolders()
            foldersErrorMessage = nil
        } catch {
            foldersErrorMessage = "Не удалось загрузить папки"
        }
    }

func loadNotes() async {
        do {
            notes = try await apiClient.notesList()
            notesErrorMessage = nil
        } catch {
            notesErrorMessage = "Не удалось загрузить заметки"
        }
    }

    // MARK: - Дерево строк

    func toggleExpanded(_ folderID: Int) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    /// Плоский список строк, отражающий развёрнутое дерево — spec: «папки
    /// можно сворачивать/разворачивать тапом по шеврону», отступ 18px на
    /// уровень (`NotesScreen.INDENT`, применяется во вью, не здесь).
    ///
    /// `ForEach` на экране читает это прямо в теле — раньше дерево собиралось
    /// заново на каждом проходе `body` (16 мс на 200 заметках, замерено
    /// 22.10.2026). Теперь дерево строится один раз на каждое изменение
    /// данных, а между ними отдаётся из кэша: ключ — папки, заметки,
    /// раскрытые папки и порядок дат.
    var rows: [NotesTreeRow] {
        let key = RowsKey(
            folders: folders,
            notes: notes,
            expanded: expandedFolderIDs,
            order: noteDateOrder
        )
        if let cachedKey = rowsCacheKey, cachedKey == key {
            return rowsCacheValue
        }
        // Счётчик перестроений — диагностика и тест: пока входные данные те
        // же, дерево пересобираться не должно.
        Self.rowsBuildCount += 1
        let built = buildRows(parentID: nil, depth: 0, ancestorContinues: [])
        rowsCacheKey = key
        rowsCacheValue = built
        return built
    }

    /// Сколько раз дерево строк собиралось заново. Растёт только на реальное
    /// перестроение, а не на отдачу из кэша.
    nonisolated(unsafe) static var rowsBuildCount = 0

    /// Ключ кэша дерева: все входные данные, от которых дерево зависит.
    private struct RowsKey: Equatable {
        let folders: [ApiJournalFolder]
        let notes: [NoteListItem]
        let expanded: Set<Int>
        let order: NotesDateOrder
    }

    /// Кэш последнего дерева. `@ObservationIgnored` — это не состояние экрана,
    /// а производная величина: её пересчёт не должен будить наблюдателей.
    @ObservationIgnored private var rowsCacheKey: RowsKey?
    @ObservationIgnored private var rowsCacheValue: [NotesTreeRow] = []

    private func buildRows(parentID: Int?, depth: Int, ancestorContinues: [Bool]) -> [NotesTreeRow] {
        let context = makeRowsContext()
        return buildRows(parentID: parentID, depth: depth, ancestorContinues: ancestorContinues, context: context)
    }

    private func buildRows(parentID: Int?, depth: Int, ancestorContinues: [Bool], context: RowsContext) -> [NotesTreeRow] {
        var out: [NotesTreeRow] = []
        let dateOrder = noteDateOrder
        let childFolders = folders.filter { $0.parentId == parentID }
        let childNotes = notes
            .filter { $0.folderId == parentID }
            .sorted { dateOrder.comparator($0, $1) }

        for (index, folder) in childFolders.enumerated() {
            let isLast = index == childFolders.count - 1 && childNotes.isEmpty
            out.append(NotesTreeRow(
                rowID: "f:\(folder.id)",
                kind: .folder(
                    folder,
                    noteCount: notesCount(inFolderTree: folder.id, context: context),
                    latestNote: latestNote(inFolderTree: folder.id, context: context)
                ),
                depth: depth,
                ancestorContinues: ancestorContinues,
                isLastChild: isLast
            ))
            if expandedFolderIDs.contains(folder.id) {
                out.append(contentsOf: buildRows(parentID: folder.id, depth: depth + 1, ancestorContinues: ancestorContinues + [!isLast], context: context))
            }
        }
        for (index, note) in childNotes.enumerated() {
            let isLast = index == childNotes.count - 1
            out.append(NotesTreeRow(
                rowID: "n:\(note.id)",
                kind: .note(note),
                depth: depth,
                ancestorContinues: ancestorContinues,
                isLastChild: isLast
            ))
        }
        return out
    }

    /// Данные одного перестроения дерева, посчитанные ОДИН раз:
    /// дата каждой заметки, заметки по папкам и поддерево каждой папки.
    ///
    /// Раньше эти три величины считались по разу на КАЖДУЮ папку: счётчик
    /// заметок и «последняя заметка» обходили весь список заметок, а дата
    /// последней заметки разбиралась заново для каждой сравниваемой пары.
    /// На 200 заметках и 10 папках это 16 мс на одно дерево.
    private struct RowsContext {
        /// Дата заметки по её id (разбор даты — один раз на заметку).
        let dates: [String: Date]
        /// Заметки по папке, в порядке исходного списка.
        let notesByFolder: [Int: [NoteListItem]]
        /// Для каждой папки — она сама и все вложенные, транзитивно.
        let folderTree: [Int: Set<Int>]
    }

    private func makeRowsContext() -> RowsContext {
        var dates: [String: Date] = [:]
        dates.reserveCapacity(notes.count)
        var notesByFolder: [Int: [NoteListItem]] = [:]
        for note in notes {
            dates[note.id] = NotesDateOrder.date(of: note)
            if let folderId = note.folderId {
                notesByFolder[folderId, default: []].append(note)
            }
        }

        var children: [Int: [Int]] = [:]
        for folder in folders {
            if let parent = folder.parentId {
                children[parent, default: []].append(folder.id)
            }
        }
        var folderTree: [Int: Set<Int>] = [:]
        for folder in folders {
            var ids: Set<Int> = []
            var stack: [Int] = [folder.id]
            while let current = stack.popLast() {
                guard ids.insert(current).inserted else { continue }
                stack.append(contentsOf: children[current] ?? [])
            }
            folderTree[folder.id] = ids
        }
        return RowsContext(dates: dates, notesByFolder: notesByFolder, folderTree: folderTree)
    }

    /// Счётчик у папки (число справа на скриншоте `notes.png`) — заметки
    /// этой папки и всех вложенных подпапок, рекурсивно.
    private func notesCount(inFolderTree folderID: Int, context: RowsContext? = nil) -> Int {
        let ctx = context ?? makeRowsContext()
        guard let ids = ctx.folderTree[folderID] else { return 0 }
        var count = 0
        for id in ids {
            count += ctx.notesByFolder[id]?.count ?? 0
        }
        return count
    }

    /// Последний документ папки учитывает и вложенные папки: именно он лучше
    /// всего отвечает на вопрос «когда тут в последний раз что-то меняли».
    func latestNote(inFolderTree folderID: Int) -> NoteListItem? {
        latestNote(inFolderTree: folderID, context: makeRowsContext())
    }

    private func latestNote(inFolderTree folderID: Int, context: RowsContext) -> NoteListItem? {
        guard let ids = context.folderTree[folderID] else { return nil }
        // Тот же порядок обхода, что у `notes.filter{...}.max(by:)`, и то же
        // правило: при равных датах остаётся ПЕРВАЯ (как у `max(by:)`).
        var best: NoteListItem?
        for note in notes {
            guard let noteFolder = note.folderId, ids.contains(noteFolder) else { continue }
            guard let current = best else {
                best = note
                continue
            }
            let noteDate = context.dates[note.id] ?? .distantPast
            let bestDate = context.dates[current.id] ?? .distantPast
            if bestDate < noteDate { best = note }
        }
        return best
    }

    // MARK: - Создание

    /// «Создать заметку» — spec/код сходятся: без формы, сразу
    /// `POST /notes {title:"", content:""}` в корень и переход в редактор
    /// (веб `handleCreateNote(null)`, `NotesScreen.tsx`). ⚠️ Спека отдельно
    /// упоминает FAB с формой создания — в живом коде FAB убран 26.08.2026
    /// («три точки вместо плюсика», см. комментарий в `NotesScreen.tsx»),
    /// создание живёт только в этом меню; следую коду.
    func createNote() async -> String? {
        do {
            let note = try await apiClient.createNote(folderId: nil, content: .string(""))
            notes.insert(NoteListItem(id: note.id, title: "", folderId: nil, preview: "", createdAt: note.createdAt, updatedAt: note.updatedAt), at: 0)
            return note.id
        } catch {
            actionErrorMessage = "Не удалось выполнить действие"
            return nil
        }
    }

    func submitCreateFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isSavingFolder else { return }
        isSavingFolder = true
        defer { isSavingFolder = false }
        do {
            let folder = try await apiClient.createJournalFolder(name: name, parentId: nil)
            folders.append(folder)
            newFolderName = ""
            isCreatingFolder = false
        } catch {
            actionErrorMessage = "Не удалось создать папку"
        }
    }

    // MARK: - Режим выбора

    func enterSelecting() {
        isSelecting = true
        selectedFolderIDs = []
        selectedNoteIDs = []
    }

    func exitSelecting() {
        isSelecting = false
        selectedFolderIDs = []
        selectedNoteIDs = []
    }

    func toggleSelected(_ row: NotesTreeRow) {
        switch row.kind {
        case .folder(let folder, _, _):
            if selectedFolderIDs.contains(folder.id) { selectedFolderIDs.remove(folder.id) }
            else { selectedFolderIDs.insert(folder.id) }
        case .note(let note):
            if selectedNoteIDs.contains(note.id) { selectedNoteIDs.remove(note.id) }
            else { selectedNoteIDs.insert(note.id) }
        }
    }

    func isSelected(_ row: NotesTreeRow) -> Bool {
        switch row.kind {
        case .folder(let folder, _, _): selectedFolderIDs.contains(folder.id)
        case .note(let note): selectedNoteIDs.contains(note.id)
        }
    }

    /// «Переименовать» активно, только когда выбрана РОВНО одна папка (spec).
    var canRenameSelection: Bool { selectedFolderIDs.count == 1 && selectedNoteIDs.isEmpty }

    func renameSelectedFolder(to newName: String) async {
        guard let id = selectedFolderIDs.first else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let updated = try await apiClient.patchJournalFolder(id: id, fields: ["name": .string(name)])
            if let idx = folders.firstIndex(where: { $0.id == id }) { folders[idx] = updated }
        } catch {
            actionErrorMessage = "Не удалось выполнить действие"
        }
    }

    /// «Переместить в папку» — только заметки: `folder_id` у `user_notes`
    /// меняется через `PATCH /notes/:id`. Перемещение папок между
    /// родителями вне выбора (спека отдаёт это drag-and-drop; здесь не
    /// реализовано — см. отчёт).
    func moveSelectedNotes(toFolderID folderID: Int?) async {
        for noteID in selectedNoteIDs {
            do {
                _ = try await apiClient.patchNote(id: noteID, fields: ["folder_id": folderID.map { JSONValue.number(Double($0)) } ?? .null])
                if let idx = notes.firstIndex(where: { $0.id == noteID }) {
                    notes[idx] = NoteListItem(id: notes[idx].id, title: notes[idx].title, folderId: folderID, preview: notes[idx].preview, createdAt: notes[idx].createdAt, updatedAt: notes[idx].updatedAt)
                }
            } catch {
                actionErrorMessage = "Не удалось выполнить действие"
            }
        }
        exitSelecting()
    }

    /// Текст подтверждения удаления — «папок: N» и/или «заметок: M», только
    /// непустые части, через запятую (spec буквально).
    var deleteConfirmDescription: String {
        var parts: [String] = []
        if !selectedFolderIDs.isEmpty { parts.append("папок: \(selectedFolderIDs.count)") }
        if !selectedNoteIDs.isEmpty { parts.append("заметок: \(selectedNoteIDs.count)") }
        let list = parts.joined(separator: ", ")
        return "Будет удалено — \(list). Заметки внутри удалённых папок не пропадут: они останутся вне папок. Действие нельзя отменить."
    }

    func deleteSelected() async {
        for folderID in selectedFolderIDs {
            do { try await apiClient.deleteJournalFolder(id: folderID) } catch { /* могла уже уйти каскадом — не рушим остальное удаление */ }
        }
        for noteID in selectedNoteIDs {
            do { try await apiClient.deleteNote(id: noteID) } catch { actionErrorMessage = "Не удалось выполнить действие" }
        }
        exitSelecting()
        await load()
    }

    // MARK: - Экспорт в Markdown

    /// «Выгрузить всё в Markdown» — веб качает файлы по одному с паузой
    /// 150мс (обход блокировки серии скачиваний браузером). На native этот
    /// обход не нужен — родной `ShareLink` умеет отдать сразу МАССИВ
    /// файлов одним системным листом «Поделиться», это и используется
    /// (упрощение в правильную сторону, названо в отчёте).
    func exportAllToMarkdownFiles() async -> [URL] {
        isExporting = true
        defer { isExporting = false }
        var urls: [URL] = []
        for note in notes {
            if let url = await exportNoteToMarkdownFile(noteID: note.id, title: note.title) {
                urls.append(url)
            }
        }
        return urls
    }

    func exportNoteToMarkdownFile(noteID: String, title: String) async -> URL? {
        do {
            let full = try await apiClient.note(id: noteID, format: "markdown")
            // Markdown лежит в отдельном поле, `content` при `?format=markdown`
            // остаётся TipTap JSON — см. `NoteEditorViewModel.exportToMarkdownFile()`.
            let markdown = full.markdown ?? full.content?.stringValue ?? ""
            let name = safeFileName(title)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            actionErrorMessage = "Не удалось выгрузить"
            return nil
        }
    }

    private func safeFileName(_ title: String, fallback: String = "Заметка") -> String {
        let base = (title.isEmpty ? fallback : title).replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
        return "\(String(base.prefix(80))).md"
    }
}

enum NotesDateOrder: CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: Self { self }

    var title: String {
        switch self {
        case .newestFirst: "Сначала новые"
        case .oldestFirst: "Сначала старые"
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: "arrow.down"
        case .oldestFirst: "arrow.up"
        }
    }

    func comparator(_ lhs: NoteListItem, _ rhs: NoteListItem) -> Bool {
        let left = Self.date(of: lhs)
        let right = Self.date(of: rhs)
        if left == right {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        switch self {
        case .newestFirst: return left > right
        case .oldestFirst: return left < right
        }
    }

    static func date(of note: NoteListItem) -> Date {
        note.updatedAt.flatMap(DateFormats.sqliteUTC)
            ?? note.createdAt.flatMap(DateFormats.sqliteUTC)
            ?? .distantPast
    }
}

/// Строка плоского списка — папка или заметка на своей глубине, с
/// разметкой направляющих линий (spec: «вертикальные линии с уголками на
/// месте последнего элемента ветки»).
struct NotesTreeRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder(ApiJournalFolder, noteCount: Int, latestNote: NoteListItem?)
        case note(NoteListItem)
    }

    let rowID: String
    let kind: Kind
    let depth: Int
    /// Для каждого уровня-предка — продолжается ли его вертикальная линия
    /// ниже (т.е. у предка есть ещё не показанные соседи после него).
    let ancestorContinues: [Bool]
    /// Эта строка — последняя среди своих соседей (рисуем «уголок», не «палку»).
    let isLastChild: Bool

    var id: String { rowID }
}
