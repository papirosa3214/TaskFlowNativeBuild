import SwiftUI

// ═══════════ NotesScreen — «Дневник» (spec/SCREENS-2.md §1) ═══════════
//
// Была своя рисованная шапка (обходила то, что у `TFScreenHeader.large`
// нет leading-слота под стрелку «Назад») — просьба владельца 03.09.2026
// («шапка кривущая, нужны нативные кнопки») перевела её на `tfNativeHeader`
// + системный `Menu` вместо самодельного `.popover`, тем же приёмом, что
// уже стоит на Today/Settings/Upcoming/Agents. Системная стрелка «Назад»
// подставляется стеком навигации сама — свою больше не рисуем.
public struct NotesScreen: View {
    @State private var viewModel = NotesViewModel()

    /// Открыть сразу на этой папке (её и предков разворачиваем, к ней же
    /// скроллим) — просьба владельца 03.09.2026: шеврон «Документация» у
    /// проекта вёл на общий несвязанный корень Дневника, не на папку,
    /// показанную в превью карточки проекта. `nil` — обычный корень, как раньше.
    private let focusFolderID: Int?

    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var showMovePicker = false
    @State private var showDeleteConfirm = false
    @State private var pendingNoteID: String?
    @State private var shareURLs: [URL] = []
    @State private var showShareSheet = false

    public init(focusFolderID: Int? = nil) {
        self.focusFolderID = focusFolderID
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    TFErrorBanner(viewModel.foldersErrorMessage)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                    TFErrorBanner(viewModel.notesErrorMessage)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                    TFErrorBanner(viewModel.actionErrorMessage)
                        .padding(.horizontal, TFSpacing.screenHorizontal)

                    if viewModel.isCreatingFolder {
                        createFolderRow
                    }

                    if viewModel.isLoading && !viewModel.hasAnyContent {
                        TFLoading(.block)
                            .frame(maxWidth: .infinity)
                    } else if !viewModel.hasAnyContent && !viewModel.isCreatingFolder {
                        TFEmptyState(
                            icon: "book",
                            text: "Записей пока нет\nЗаметки складываются в папки — перетаскиванием или сразу при создании.",
                            actionTitle: "Создать заметку"
                        ) { Task { await createNoteAndNavigate() } }
                        .padding(.top, TFSpacing.xl)
                    } else {
                        ForEach(viewModel.rows) { row in
                            rowView(row)
                        }
                    }
                }
                .padding(.vertical, TFSpacing.sm)
            }
            .task {
                await viewModel.load()
                guard let focusFolderID else { return }
                expandAncestors(of: focusFolderID)
                // Короткая пауза — дать LazyVStack отрисовать развёрнутые
                // строки, прежде чем скроллить к ним (иначе scrollTo не
                // находит ещё не выложенный id).
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation { proxy.scrollTo("f:\(focusFolderID)", anchor: .top) }
            }
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Дневник", displayMode: .inline)
        .toolbar {
            if viewModel.isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { viewModel.exitSelecting() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    selectionMenu
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    kebabMenu
                }
            }
        }
        // Редактор берём из общей фабрики маршрутов: пока экран не написан,
        // она отдаёт заглушку, и список заметок от этого не ломается.
        .navigationDestination(item: $pendingNoteID) { id in
            routeDestination(.noteEditor(noteID: id))
        }
        .sheet(isPresented: $showMovePicker) {
            FolderPickerSheet(folders: viewModel.folders, title: "Переместить в папку") { folderID in
                Task { await viewModel.moveSelectedNotes(toFolderID: folderID) }
            }
        }
        .alert("Переименовать папку", isPresented: $showRenameSheet) {
            TextField("Название", text: $renameText)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") { Task { await viewModel.renameSelectedFolder(to: renameText); viewModel.exitSelecting() } }
        }
        .alert("Удалить отмеченное?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { Task { await viewModel.deleteSelected() } }
        } message: {
            Text(viewModel.deleteConfirmDescription)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareURLs)
        }
    }

    // MARK: - Меню «…» (нативные, см. комментарий в начале файла)

    private var kebabMenu: some View {
        Menu {
            Button { Task { await createNoteAndNavigate() } } label: {
                Label("Создать заметку", systemImage: "doc.text")
            }
            Button { viewModel.isCreatingFolder = true } label: {
                Label("Создать папку", systemImage: "folder")
            }
            Button { viewModel.enterSelecting() } label: {
                Label("Выбрать элементы", systemImage: "checklist")
            }
            Button {
                Task {
                    shareURLs = await viewModel.exportAllToMarkdownFiles()
                    if !shareURLs.isEmpty { showShareSheet = true }
                }
            } label: {
                Label("Выгрузить всё в Markdown", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Действия")
    }

    private var selectionMenu: some View {
        Menu {
            Button {
                renameText = ""
                showRenameSheet = true
            } label: {
                Label("Переименовать", systemImage: "pencil")
            }
            .disabled(!viewModel.canRenameSelection)

            Button { showMovePicker = true } label: {
                Label("Переместить в папку", systemImage: "folder")
            }
            .disabled(viewModel.selectedNoteIDs.isEmpty)

            Button {
                Task {
                    var urls: [URL] = []
                    for id in viewModel.selectedNoteIDs {
                        if let note = viewModel.notes.first(where: { $0.id == id }),
                           let url = await viewModel.exportNoteToMarkdownFile(noteID: id, title: note.title) {
                            urls.append(url)
                        }
                    }
                    shareURLs = urls
                    if !shareURLs.isEmpty { showShareSheet = true }
                }
            } label: {
                Label("Выгрузить в Markdown", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Удалить", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .disabled(!viewModel.hasSelection)
        .accessibilityLabel("Действия с выбранным")
    }

    // MARK: - Инлайн-форма «Создать папку»

    private var createFolderRow: some View {
        HStack(spacing: TFSpacing.sm) {
            TFTextField("Название папки", text: $viewModel.newFolderName)
            Button(viewModel.isSavingFolder ? "Создаём…" : "Создать") {
                Task { await viewModel.submitCreateFolder() }
            }
            .tfText(.body)
            .foregroundStyle(Color.tfRed)
            .disabled(viewModel.isSavingFolder || viewModel.newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Отмена") { viewModel.isCreatingFolder = false; viewModel.newFolderName = "" }
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
    }

    // MARK: - Строка дерева

    @ViewBuilder
    private func rowView(_ row: NotesTreeRow) -> some View {
        switch row.kind {
        case .folder(let folder, let noteCount):
            folderRow(row, folder: folder, noteCount: noteCount)
        case .note(let note):
            noteRow(row, note: note)
        }
    }

    private func folderRow(_ row: NotesTreeRow, folder: ApiJournalFolder, noteCount: Int) -> some View {
        Button {
            if viewModel.isSelecting { viewModel.toggleSelected(row) }
            else { viewModel.toggleExpanded(folder.id) }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                indentGuides(row)
                if viewModel.isSelecting {
                    TFCheckbox(isChecked: viewModel.isSelected(row))
                }
                Image(systemName: viewModel.expandedFolderIDs.contains(folder.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tfDim)
                    .frame(width: 16)
                Image(systemName: "folder")
                    .foregroundStyle(Color.tfSub)
                Text(folder.name)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Spacer()
                Text("\(noteCount)")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
    }

    private func noteRow(_ row: NotesTreeRow, note: NoteListItem) -> some View {
        Group {
            if viewModel.isSelecting {
                Button { viewModel.toggleSelected(row) } label: { noteRowContent(row, note: note) }
                    .buttonStyle(TFTapRowStyle())
            } else {
                NavigationLink(value: AppRoute.noteEditor(noteID: note.id)) {
                    noteRowContent(row, note: note)
                }
                .buttonStyle(TFTapRowStyle())
            }
        }
    }

    private func noteRowContent(_ row: NotesTreeRow, note: NoteListItem) -> some View {
        HStack(spacing: TFSpacing.sm) {
            indentGuides(row)
            if viewModel.isSelecting {
                TFCheckbox(isChecked: viewModel.isSelected(row))
            }
            Image(systemName: "doc.text")
                .foregroundStyle(Color.tfDim)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Без названия" : note.title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Направляющие линии вложенности — 18px на уровень (spec «INDENT»).
    /// Упрощение против «уголков» файлового менеджера: рисуем сплошную
    /// вертикальную чёрточку на каждом уровне-предке, у которого после
    /// текущей строки ещё есть соседи (иначе — пусто, как и должно быть
    /// у последнего элемента ветки).
    private func indentGuides(_ row: NotesTreeRow) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<row.depth, id: \.self) { level in
                Rectangle()
                    .fill(level < row.ancestorContinues.count && row.ancestorContinues[level] ? Color.tfStroke : Color.clear)
                    .frame(width: 1)
                    .frame(width: 18)
            }
        }
    }

    private func createNoteAndNavigate() async {
        if let id = await viewModel.createNote() {
            pendingNoteID = id
        }
    }

    /// Разворачивает саму папку и всех её предков по цепочке `parentId` —
    /// иначе целевая папка (и её заметки) остаётся свёрнутой глубоко в
    /// дереве, а `scrollTo` в `.task` выше не находит невыложенную строку.
    private func expandAncestors(of folderID: Int) {
        var current: Int? = folderID
        while let id = current {
            viewModel.expandedFolderIDs.insert(id)
            current = viewModel.folders.first { $0.id == id }?.parentId
        }
    }
}

/// Обёртка `UIActivityViewController` — «Выгрузить в Markdown» отдаёт
/// системный лист «Поделиться» с уже готовыми файлами (сохранение в
/// Файлы/AirDrop/шаринг — вариант из спеки «серия файлов в Файлы/шеринг»).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
