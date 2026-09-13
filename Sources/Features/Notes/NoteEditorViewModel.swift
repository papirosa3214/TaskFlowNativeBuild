import Foundation
import Observation

// Вью-модель редактора заметки — spec/SCREENS-2.md §2. Своя `APIClient()`
// (не из окружения) — тот же паттерн, что у `NotesViewModel` по соседству.
@MainActor
@Observable
final class NoteEditorViewModel {
    private let apiClient = APIClient()
    let noteID: String

    var document = NoteDocument.empty
    var folders: [ApiJournalFolder] = []
    var isLoading = false
    var loadErrorMessage: String?
    var saveState: SaveState = .idle
    /// Куда программно поставить курсор после структурной правки (Enter/
    /// Backspace/разделитель) — читает и сбрасывает экран (см. `NoteEditorScreen`).
    var pendingFocus: PendingFocus?

    // Меню AI (sparkles) — spec §2 «Меню AI».
    var aiBusy = false
    var aiLabel = "ИИ думает…"
    var aiErrorMessage: String?
    var extractedTasks: [ExtractedNoteTask] = []
    var showExtractedTasksSheet = false

    // Меню «Ещё» / удаление / перемещение / экспорт.
    var actionErrorMessage: String?

    enum SaveState { case idle, saving, saved, error }
    struct PendingFocus: Equatable { let blockID: UUID; let position: NoteCursorPosition }

    private var saveGeneration = 0
    private var saveTask: Task<Void, Never>?

    init(noteID: String) {
        self.noteID = noteID
    }

    var statusLabel: String {
        switch saveState {
        case .idle: ""
        case .saving: "Сохранение…"
        case .saved: "Сохранено"
        case .error: "Не удалось сохранить"
        }
    }

    // MARK: - Загрузка

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let foldersTask = apiClient.journalFolders()
        do {
            // Тянем с ?format=markdown: сервер ДОБАВЛЯЕТ поле `note.markdown`
            // (см. APIClient+Notes.swift) — результат `tiptapToMarkdown.ts`.
            // Если сервер его не вернул (старый билд / битый ответ), фолбэк
            // на парсинг TipTap JSON из `content` — пусть старые заметки
            // хотя бы откроются, а не упадут.
            let note = try await apiClient.note(id: noteID, format: "markdown")
            if let md = note.markdown, !md.isEmpty {
                document = NoteDocument(blocks: MarkdownParser.parse(md))
            } else {
                document = NoteDocument.decode(fromJSONString: note.content?.stringValue)
            }
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = "Не удалось загрузить заметку"
        }
        folders = (try? await foldersTask) ?? []
    }

    // MARK: - Автосохранение (debounce 800мс, spec §2 «Автосохранение»)

    private func scheduleSave() {
        saveState = .saving
        saveGeneration += 1
        let myGeneration = saveGeneration
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled, myGeneration == self.saveGeneration else { return }
            await self.flush()
        }
    }

    private func flush() async {
        let fields: [String: JSONValue] = ["title": .string(document.derivedTitle), "content": .string(document.encodeToJSONString())]
        do {
            _ = try await apiClient.patchNote(id: noteID, fields: fields)
            saveState = .saved
            fadeSavedStatus()
        } catch {
            saveState = .error
        }
    }

    /// «Сохранено» — уведомление, а не состояние: висеть над текстом ему
    /// незачем, гаснет через пару секунд. Ошибка остаётся, пока следующее
    /// сохранение не пройдёт: её человек должен увидеть, даже если отвлёкся.
    private func fadeSavedStatus() {
        let generation = saveGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.saveGeneration == generation, self.saveState == .saved else { return }
            self.saveState = .idle
        }
    }

    /// Принудительный немедленный сброс при уходе с экрана — без ожидания
    /// debounce (spec: «иначе последние нажатия клавиш теряются»). Не ждёт
    /// ответа сервера (экран к этому моменту уже закрывается), как и веб.
    ///
    /// Пустая заметка при выходе — удаляем, а не сохраняем: «Создать
    /// заметку» создаёт её на сервере СРАЗУ, ещё до единого нажатия клавиши
    /// (spec) — если уйти, ничего не напечатав, раньше черновик так и
    /// оставался висеть в Дневнике безымянным навсегда (просьба владельца
    /// 03.09.2026: «чтобы по уму создавались», источник кучи «Без названия»,
    /// см. LOCK-072/073 в AGENT-WORK-SCOPES.md). Правило одно и то же и для
    /// только что созданной, и для когда-то не пустой, а теперь вычищенной
    /// заметки — пустая заметка ценности не несёт независимо от истории.
    func flushOnExit() {
        saveTask?.cancel()
        saveTask = nil
        let client = apiClient
        let id = noteID
        if document.isEffectivelyEmpty {
            Task.detached {
                try? await client.deleteNote(id: id)
            }
            return
        }
        let fields: [String: JSONValue] = ["title": .string(document.derivedTitle), "content": .string(document.encodeToJSONString())]
        Task.detached {
            _ = try? await client.patchNote(id: id, fields: fields)
        }
    }

    // MARK: - Операции над блоками

    private func index(of blockID: UUID?) -> Int? {
        guard let blockID else { return nil }
        return document.blocks.firstIndex { $0.id == blockID }
    }

    /// Правка текста блока — приходит и от печати (делегат UITextView), и
    /// от тулбар-переключателей марок (после программной мутации textStorage).
    ///
    /// Ячейка таблицы — тоже отдельный `UITextView` со своим контроллером,
    /// но своего блока в документе у неё нет: `blockID` тогда — это id
    /// ЯЧЕЙКИ. Разбор идёт здесь, а не отдельным методом, потому что зовут
    /// эту точку не только печать, но и клавиатурная панель, диктовка и
    /// вставка ответа ИИ — все они знают ровно один идентификатор, тот, что
    /// лежит в `NoteEditorFocusState.blockID`.
    func updateRuns(blockID: UUID, runs: [RichRun]) {
        if let idx = index(of: blockID) {
            document.blocks[idx].runs = runs
            scheduleSave()
            return
        }
        updateTableCell(cellID: blockID, runs: runs)
    }

    // MARK: - Структура таблицы: строки и столбцы

    /// Адрес ячейки в документе. Ищем перебором, а не держим индекс рядом с
    /// фокусом: таблиц в заметке единицы, а лишнее состояние рассинхронится
    /// на первой же правке соседнего блока.
    private func tableLocation(of cellID: UUID) -> (block: Int, row: Int, column: Int)? {
        for (blockIdx, block) in document.blocks.enumerated() {
            guard case .table(let rows) = block.kind else { continue }
            for (rowIdx, row) in rows.enumerated() {
                if let columnIdx = row.cells.firstIndex(where: { $0.id == cellID }) {
                    return (blockIdx, rowIdx, columnIdx)
                }
            }
        }
        return nil
    }

    /// Новая строка всегда обычная, не шапка: шапка в markdown ровно одна —
    /// первая, и вторая строка-шапка при выгрузке всё равно стала бы
    /// обычной, только пользователь бы этого не ожидал.
    func insertTableRow(below cellID: UUID) {
        guard let loc = tableLocation(of: cellID),
              case .table(var rows) = document.blocks[loc.block].kind
        else { return }
        let width = max(rows.map(\.cells.count).max() ?? 1, 1)
        let newRow = NoteTableRow(cells: (0..<width).map { _ in NoteTableCell(runs: [], isHeader: false) })
        rows.insert(newRow, at: loc.row + 1)
        document.blocks[loc.block].kind = .table(rows: rows)
        pendingFocus = PendingFocus(blockID: newRow.cells[min(loc.column, width - 1)].id, position: .start)
        scheduleSave()
    }

    /// Столбец добавляется во ВСЕ строки сразу, иначе таблица станет рваной:
    /// сервер при выгрузке добивает короткие строки пустыми ячейками, но в
    /// приложении такая таблица показалась бы с дырой.
    func insertTableColumn(after cellID: UUID) {
        guard let loc = tableLocation(of: cellID),
              case .table(var rows) = document.blocks[loc.block].kind
        else { return }
        for rowIdx in rows.indices {
            let isHeader = rows[rowIdx].cells.first?.isHeader ?? false
            let at = min(loc.column + 1, rows[rowIdx].cells.count)
            rows[rowIdx].cells.insert(NoteTableCell(runs: [], isHeader: isHeader), at: at)
        }
        document.blocks[loc.block].kind = .table(rows: rows)
        let target = rows[loc.row].cells[min(loc.column + 1, rows[loc.row].cells.count - 1)]
        pendingFocus = PendingFocus(blockID: target.id, position: .start)
        scheduleSave()
    }

    func deleteTableRow(containing cellID: UUID) {
        guard let loc = tableLocation(of: cellID),
              case .table(var rows) = document.blocks[loc.block].kind
        else { return }
        rows.remove(at: loc.row)
        applyTable(rows, at: loc.block)
    }

    func deleteTableColumn(containing cellID: UUID) {
        guard let loc = tableLocation(of: cellID),
              case .table(var rows) = document.blocks[loc.block].kind
        else { return }
        for rowIdx in rows.indices where loc.column < rows[rowIdx].cells.count {
            rows[rowIdx].cells.remove(at: loc.column)
        }
        rows.removeAll { $0.cells.isEmpty }
        applyTable(rows, at: loc.block)
    }

    /// Таблица без строк (или из которой вынули последний столбец) — уже не
    /// таблица: блок уходит целиком, а не остаётся пустой рамкой. Если он
    /// был в заметке единственным, на его месте остаётся пустой параграф —
    /// документу без блоков редактору некуда поставить курсор.
    private func applyTable(_ rows: [NoteTableRow], at blockIdx: Int) {
        if rows.isEmpty {
            document.blocks.remove(at: blockIdx)
            if document.blocks.isEmpty { document.blocks = [NoteBlock(kind: .paragraph)] }
        } else {
            document.blocks[blockIdx].kind = .table(rows: rows)
        }
        scheduleSave()
    }

    private func updateTableCell(cellID: UUID, runs: [RichRun]) {
        for (blockIdx, block) in document.blocks.enumerated() {
            guard case .table(var rows) = block.kind else { continue }
            for (rowIdx, row) in rows.enumerated() {
                guard let cellIdx = row.cells.firstIndex(where: { $0.id == cellID }) else { continue }
                rows[rowIdx].cells[cellIdx].runs = runs
                document.blocks[blockIdx].kind = .table(rows: rows)
                scheduleSave()
                return
            }
        }
    }

    func toggleHeading(_ level: Int, blockID: UUID?) {
        guard let idx = index(of: blockID) else { return }
        if case .heading(let current) = document.blocks[idx].kind, current == level {
            document.blocks[idx].kind = .paragraph
        } else {
            document.blocks[idx].kind = .heading(level: level)
        }
        scheduleSave()
    }

    enum ListToggle { case bullet, ordered, task }

    func toggleList(_ kind: ListToggle, blockID: UUID?) {
        guard let idx = index(of: blockID) else { return }
        let current = document.blocks[idx].kind
        let isSame: Bool
        switch (kind, current) {
        case (.bullet, .bulletItem), (.ordered, .orderedItem), (.task, .taskItem): isSame = true
        default: isSame = false
        }
        if isSame {
            document.blocks[idx].kind = .paragraph
            document.blocks[idx].level = 0
        } else {
            switch kind {
            case .bullet: document.blocks[idx].kind = .bulletItem
            case .ordered: document.blocks[idx].kind = .orderedItem
            case .task: document.blocks[idx].kind = .taskItem(checked: false)
            }
        }
        scheduleSave()
    }

    func toggleQuote(blockID: UUID?) {
        guard let idx = index(of: blockID) else { return }
        document.blocks[idx].kind = (document.blocks[idx].kind == .blockquote) ? .paragraph : .blockquote
        scheduleSave()
    }

    /// Переключение блока кода — текст переносится как ЕДИНЫЙ прогон без
    /// марок в обе стороны (модель `NoteBlock` соседа хранит codeBlock так
    /// же — см. комментарий в `NoteDocument.swift`), инлайн-форматирование
    /// параграфа при входе в код теряется (веб-тулбар тоже не сохраняет
    /// его при переключении — источник ограничения общий, не наше решение).
    func toggleCodeBlock(blockID: UUID?) {
        guard let idx = index(of: blockID) else { return }
        let block = document.blocks[idx]
        if case .codeBlock = block.kind {
            document.blocks[idx].kind = .paragraph
        } else {
            document.blocks[idx].kind = .codeBlock(language: nil)
        }
        document.blocks[idx].runs = [RichRun(text: block.plainText)]
        scheduleSave()
    }

    func insertHorizontalRule(afterBlockID: UUID?) {
        guard let idx = index(of: afterBlockID) else { return }
        let hr = NoteBlock(kind: .horizontalRule)
        let paragraph = NoteBlock(kind: .paragraph)
        document.blocks.insert(contentsOf: [hr, paragraph], at: idx + 1)
        pendingFocus = PendingFocus(blockID: paragraph.id, position: .start)
        scheduleSave()
    }

    func toggleTaskChecked(blockID: UUID) {
        guard let idx = index(of: blockID), case .taskItem(let checked) = document.blocks[idx].kind else { return }
        document.blocks[idx].kind = .taskItem(checked: !checked)
        scheduleSave()
    }

    /// Enter внутри блока — раскладка зависит от типа (см. комментарий у
    /// `NoteBlockTextView.Coordinator.shouldChangeTextIn`, блок кода туда не
    /// доходит вовсе, перенос там литеральный).
    func handleSplit(blockID: UUID, atUTF16Offset offset: Int) {
        guard let idx = index(of: blockID) else { return }
        let block = document.blocks[idx]
        let (before, after) = MarkdownText.splitRuns(block.runs, atUTF16Offset: offset)

        switch block.kind {
        case .bulletItem, .orderedItem, .taskItem:
            let beforeEmpty = before.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if beforeEmpty && after.isEmpty {
                // Enter на пустом пункте списка — конвенция редакторов
                // списков: выходим из списка вместо создания пустого пункта.
                document.blocks[idx].kind = .paragraph
                document.blocks[idx].level = 0
                pendingFocus = PendingFocus(blockID: block.id, position: .start)
                scheduleSave()
                return
            }
            document.blocks[idx].runs = before
            var newKind = block.kind
            if case .taskItem = newKind { newKind = .taskItem(checked: false) }
            let newBlock = NoteBlock(kind: newKind, level: block.level, runs: after)
            document.blocks.insert(newBlock, at: idx + 1)
            pendingFocus = PendingFocus(blockID: newBlock.id, position: .start)

        case .blockquote:
            document.blocks[idx].runs = before
            let newBlock = NoteBlock(kind: .blockquote, runs: after)
            document.blocks.insert(newBlock, at: idx + 1)
            pendingFocus = PendingFocus(blockID: newBlock.id, position: .start)

        default:
            // Параграф и заголовок — Enter в заголовке продолжает обычным
            // параграфом, а не повторным заголовком (упрощение против
            // точной раскладки клавиш StarterKit, названо в отчёте).
            // horizontalRule сюда не попадает — у него нет текстового поля.
            document.blocks[idx].runs = before
            let newBlock = NoteBlock(kind: .paragraph, runs: after)
            document.blocks.insert(newBlock, at: idx + 1)
            pendingFocus = PendingFocus(blockID: newBlock.id, position: .start)
        }
        scheduleSave()
    }

    /// Backspace на пустом выделении в самом начале блока.
    func handleBackspaceAtStart(blockID: UUID) {
        guard let idx = index(of: blockID) else { return }
        let block = document.blocks[idx]

        if !isPlainParagraph(block.kind) {
            // Не-параграф — сперва разжаловать в параграф (второй Backspace
            // уже сольёт его с предыдущим блоком). Стандартная конвенция
            // WYSIWYG-редакторов (Notion/Bear и т.п.).
            document.blocks[idx].kind = .paragraph
            document.blocks[idx].level = 0
            scheduleSave()
            return
        }

        guard idx > 0 else { return } // первый блок документа — сливать не с чем
        let prevIdx = idx - 1

        if case .horizontalRule = document.blocks[prevIdx].kind {
            // У разделителя нет текстового поля — Backspace в блоке сразу
            // после него удаляет саму линию, а не «сливается» с ней.
            document.blocks.remove(at: prevIdx)
            pendingFocus = PendingFocus(blockID: block.id, position: .start)
            scheduleSave()
            return
        }

        let boundary = document.blocks[prevIdx].runs.reduce(0) { $0 + ($1.text as NSString).length }
        document.blocks[prevIdx].runs += block.runs
        let prevID = document.blocks[prevIdx].id
        document.blocks.remove(at: idx)
        pendingFocus = PendingFocus(blockID: prevID, position: .offset(boundary))
        scheduleSave()
    }

    private func isPlainParagraph(_ kind: BlockKind) -> Bool {
        if case .paragraph = kind { return true }
        return false
    }

    /// Весь текст документа — используется меню AI, когда в фокусном блоке
    /// нет выделения (spec §2 «Меню AI»: «применяется ко всему документу
    /// целиком, если нет выделения»).
    var wholeDocumentText: String {
        document.blocks.map(\.plainText).joined(separator: "\n")
    }

    // MARK: - Меню ИИ (sparkles)

    /// ⚠️ Упрощение против веба: там выделение — единый диапазон ProseMirror
    /// через границы блоков; здесь блок = отдельный `UITextView`, поэтому
    /// «выделение» — это выделение ВНУТРИ фокусного блока, не через весь
    /// документ. Без выделения — берём документ целиком, как и веб.
    func runAssist(_ action: JournalAssistAction, selectedText: String?) async -> String? {
        let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? selectedText!
            : wholeDocumentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        aiErrorMessage = nil
        aiLabel = switch action {
        case .continueThought: "Продолжаю мысль…"
        case .shorten: "Сокращаю текст…"
        case .expand: "Развиваю в шаги…"
        }
        aiBusy = true
        defer { aiBusy = false }
        do {
            return try await apiClient.journalAssist(text: text, action: action)
        } catch {
            aiErrorMessage = "Не удалось выполнить действие AI"
            return nil
        }
    }

    /// Без выделения «Продолжить мысль»/«Сократить»/«Развить» применяются
    /// ко всему документу — зеркалит веб (`insertContentAt` на весь
    /// диапазон документа). С выделением — правку внутри одного блока
    /// делает сам экран через `NoteBlockTextController` (там же, где текст
    /// и был выделен), сюда такой случай не доходит.
    func applyAssistResultToWholeDocument(_ text: String, action: JournalAssistAction) {
        let newBlocks = Self.blocksFromAIText(text)
        guard !newBlocks.isEmpty else { return }
        switch action {
        case .continueThought:
            document.blocks.append(contentsOf: newBlocks)
        case .shorten, .expand:
            document.blocks = newBlocks
        }
        scheduleSave()
    }

    /// Разбирает plain-text ответ ИИ в блоки — зеркалит `resultToHtml` веба
    /// (`src/screens/NoteEditorScreen.tsx`): строки «- пункт» собираются в
    /// маркированный список, иначе каждая строка — свой параграф.
    private static func blocksFromAIText(_ text: String) -> [NoteBlock] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        if lines.allSatisfy({ $0.hasPrefix("- ") }) {
            return lines.map { NoteBlock(kind: .bulletItem, runs: [RichRun(text: String($0.dropFirst(2)))]) }
        }
        return lines.map { NoteBlock(kind: .paragraph, runs: [RichRun(text: $0)]) }
    }

    func runExtractTasks(selectedText: String?) async {
        let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? selectedText!
            : wholeDocumentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        aiErrorMessage = nil
        aiLabel = "Собираю задачи…"
        aiBusy = true
        defer { aiBusy = false }
        do {
            let tasks = try await apiClient.extractTasksFromNote(text: text)
            extractedTasks = tasks
            if tasks.isEmpty {
                aiErrorMessage = "AI не нашёл в тексте конкретных задач"
            } else {
                showExtractedTasksSheet = true
            }
        } catch {
            aiErrorMessage = "Не удалось извлечь задачи"
        }
    }

    // MARK: - Меню «Ещё»

    func deleteNote() async -> Bool {
        do {
            try await apiClient.deleteNote(id: noteID)
            return true
        } catch {
            actionErrorMessage = "Не удалось выполнить действие"
            return false
        }
    }

    func moveToFolder(_ folderID: Int?) async {
        do {
            _ = try await apiClient.patchNote(id: noteID, fields: ["folder_id": folderID.map { JSONValue.number(Double($0)) } ?? .null])
        } catch {
            actionErrorMessage = "Не удалось выполнить действие"
        }
    }

    /// Экспорт в Markdown — сервер сам конвертирует TipTap JSON → md
    /// (`GET /notes/:id?format=markdown`), клиенту не нужен свой конвертер.
    func exportToMarkdownFile() async -> URL? {
        do {
            let full = try await apiClient.note(id: noteID, format: "markdown")
            // `?format=markdown` кладёт результат конвертации в отдельное поле
            // `markdown`, а `content` оставляет TipTap-строкой как есть — читать
            // `content` значило выгрузить JSON вместо markdown.
            let markdown = full.markdown ?? full.content?.stringValue ?? ""
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(document.derivedTitle))
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
