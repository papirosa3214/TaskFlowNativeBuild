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
    var reading = NoteReadingState()
    var isSavingMarkdown = false
    var folders: [ApiJournalFolder] = []
    var isLoading = false
    var loadErrorMessage: String?
    var saveState: SaveState = .idle

    // Меню AI (sparkles) — spec §2 «Меню AI».
    var aiBusy = false
    var aiLabel = "ИИ думает…"
    var aiErrorMessage: String?
    var extractedTasks: [ExtractedNoteTask] = []
    var showExtractedTasksSheet = false
    /// Собранная постановка (родитель + дочерние) — показываем карточку.
    var createdDraftTask: StructureDraftResult?

    // Меню «Ещё» / удаление / перемещение / экспорт.
    var actionErrorMessage: String?

    enum SaveState { case idle, saving, saved, error }

    private var saveGeneration = 0
    private var saveTask: Task<Void, Never>?
    private var hasDocumentChanges = false

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
            // Markdown нужен только как исходник редактора, чтение — из серверного документа.
            let note = try await apiClient.note(id: noteID, format: "markdown")
            document = try NoteDocument.fromServer(note.content)
            reading.load(note.markdown ?? MarkdownEncoder.encode(document.blocks))
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = "Не удалось загрузить заметку"
        }
        folders = (try? await foldersTask) ?? []
    }

    // MARK: - Автосохранение (debounce 800мс, spec §2 «Автосохранение»)

    private func scheduleSave() {
        if !reading.isEditing {
            reading.load(MarkdownEncoder.encode(document.blocks))
            hasDocumentChanges = true
        }
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
        if reading.isEditing {
            await saveMarkdownDraft()
            return
        }
        guard hasDocumentChanges else { return }
        let generation = saveGeneration
        let fields: [String: JSONValue] = ["title": .string(document.derivedTitle), "content": .string(document.encodeToJSONString())]
        do {
            _ = try await apiClient.patchNote(id: noteID, fields: fields)
            if generation == saveGeneration { hasDocumentChanges = false }
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

    func flushOnExit() {
        saveTask?.cancel()
        saveTask = nil
        if reading.isEditing, reading.hasChanges {
            Task {
                while isSavingMarkdown { try? await Task.sleep(for: .milliseconds(50)) }
                await saveMarkdownDraft()
            }
        } else if hasDocumentChanges {
            Task { await flush() }
        }
    }

    func beginMarkdownEditing() async {
        guard !isLoading, loadErrorMessage == nil else { return }
        if hasDocumentChanges {
            saveTask?.cancel()
            saveTask = nil
            await flush()
            guard !hasDocumentChanges else { return }
        }
        reading.beginEditing()
    }

    func markdownDidChange() {
        guard reading.isEditing else { return }
        scheduleSave()
    }

    func finishMarkdownEditing() async {
        saveTask?.cancel()
        saveTask = nil
        await saveMarkdownDraft()
        _ = reading.finishEditing()
    }

    private func saveMarkdownDraft() async {
        guard reading.hasChanges, !isSavingMarkdown else { return }
        let snapshot = reading.draft
        isSavingMarkdown = true
        saveState = .saving
        defer { isSavingMarkdown = false }
        do {
            let saved = try await apiClient.patchNote(id: noteID, fields: ["markdown": .string(snapshot)])
            let preparedDocument = try NoteDocument.fromServer(saved.content)
            reading.didSave(snapshot)
            document = preparedDocument
            saveState = .saved
            fadeSavedStatus()
            if reading.hasChanges { scheduleSave() }
        } catch {
            saveState = .error
        }
    }

    // MARK: - Операции над блоками

    /// Структурные правки документа делает общий `BlockDocumentEditor`
    /// (`Sources/Features/Markdown/BlockDocumentEditor.swift`) — тот же, что
    /// стоит в описании задачи: он мутирует `document.blocks` напрямую и
    /// зовёт `documentDidChange()`. Здесь остаётся только то, что относится
    /// к ЗАМЕТКЕ: сохранение на сервер и вставка текста от ИИ.
    func documentDidChange() {
        scheduleSave()
    }

    /// Правка текста блока из меню AI (в самом редакторе тот же путь идёт
    /// напрямую через `BlockDocumentOps`).
    func updateRuns(blockID: UUID, runs: [RichRun]) {
        BlockDocumentOps.updateRuns(&document.blocks, blockID: blockID, runs: runs)
        scheduleSave()
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

    /// Собрать ПОСТАНОВКУ из текста: тем же контуром, что надиктовка из чата
    /// (`/ai/structure-draft`) — родитель + шаги + дочерние карточки, черновиком
    /// без флага. Плоский «разбор задач» оставлен рядом: он про список дел,
    /// этот — про структуру работы.
    func collectDraft(selectedText: String?) async {
        let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? selectedText!
            : wholeDocumentText
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else {
            aiErrorMessage = "Для постановки текста слишком мало"
            return
        }
        aiErrorMessage = nil
        aiLabel = "Собираю постановку…"
        aiBusy = true
        defer { aiBusy = false }
        do {
            createdDraftTask = try await apiClient.structureDraft(text: text)
        } catch {
            aiErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось собрать постановку"
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
