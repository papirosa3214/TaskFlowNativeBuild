import SwiftUI

/// Фильтр списка заметок проекта по дате последнего изменения.
enum NotesDateFilter: String, CaseIterable, Identifiable {
    case day, week, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: "День"
        case .week: "Неделя"
        case .month: "Месяц"
        case .all: "Всё"
        }
    }
    /// Порог «отрезаем всё, что старше». Для `.all` — без отсечения.
    func cutoff(now: Date) -> Date? {
        switch self {
        case .day: now.addingTimeInterval(-24 * 60 * 60)
        case .week: now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month: now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .all: nil
        }
    }
}

// «Документация» — spec/SCREENS-2.md §8.1, дубль `src/components/ProjectNotes.tsx`
// (чужая папка `src/components/`, не Directory — своя копия, тот же приём
// дублирования, что у всего этого раздела). Источник данных — ОДИН запрос
// `directoryProjectDocs` (`APIClient+Directory.swift`, сервер уже разворачивает
// поддерево папок сам), плюс отдельно список ВСЕХ папок Дневника — он нужен
// только для пикера «Выбрать папку», которого одного запроса не даёт.
//
// Свой `APIClient()` — тот же безопасный приём, что весь остальной проект
// (второй экземпляр без состояния, см. `APIClient+Directory.swift`).
struct ProjectNotesSection: View {
    let project: ApiProject
    /// ProjectTasksScreen передаёт колбэк, который обновляет `notesFolderId`
    /// локально (свежий `ApiProject` из `patchProject`) — сама секция стор
    /// проектов не трогает, только сообщает наверх, что изменилось.
    let onProjectPatched: (ApiProject) -> Void

    @State private var docs: APIClient.DirectoryProjectDocs?
    @State private var allFolders: [ApiJournalFolder] = []
    @State private var isLoading = true
    @State private var busy = false
    @State private var pickerOpen = false
    @State private var detachConfirm = false
    @State private var pendingNoteID: String?
    @State private var errorMessage: String?
    @State private var dateFilter: NotesDateFilter = .all
    /// Папка документации свёрнута/развёрнута. По умолчанию развёрнута — как
    /// было видно до этой правки; тап по строкке папки сворачивает документы
    /// в неё, а не уводит на экран папки (владелец 05.10.2026: «я просто
    /// должен сворачивать папку, никуда я не провалюсь»).
    @State private var docsExpanded: Bool
    /// Раскрытые папки задач внутри папки документации.
    @State private var openFolders: Set<Int> = []

    /// Свёрнутость документации помнится по проекту (владелец 06.10.2026:
    /// «сворачиваю, выхожу, захожу — опять развёрнута»).
    private var docsExpandedKey: String { "project.docs.expanded.\(project.id)" }

    init(project: ApiProject, onProjectPatched: @escaping (ApiProject) -> Void) {
        self.project = project
        self.onProjectPatched = onProjectPatched
        _docsExpanded = State(initialValue: TaskCardDisclosureState.flag("project.docs.expanded.\(project.id)", default: true))
    }

    private let apiClient = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack {
                Text("Документация")
                    // Единый заголовок секции — 13 pt `tfSub`
                    // (LOCK-TYPOGRAPHY-UNIFY): было `.title` 17.
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                Spacer()
                if docs?.folder != nil {
                    TFIconButton("plus", label: "Добавить документ") { Task { await addNote() } }
                }
            }

            if isLoading {
                TFLoading()
            } else if let folder = docs?.folder {
                folderSection(folder)
            } else {
                emptySection
            }

            TFErrorBanner(errorMessage, variant: .block)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.top, TFSpacing.xl)
        .task { await load() }
        .navigationDestination(item: $pendingNoteID) { id in routeDestination(.noteEditor(noteID: id)) }
        .confirmationDialog("Открепить папку?", isPresented: $detachConfirm, titleVisibility: .visible) {
            Button("Открепить", role: .destructive) { Task { await detach() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сама папка и документы внутри останутся на месте — в Базе знаний. Здесь просто пропадёт эта секция.")
        }
        .confirmationDialog("Выбрать папку", isPresented: $pickerOpen, titleVisibility: .visible) {
            ForEach(allFolders) { folder in
                Button(folder.name) { Task { await attach(folder.id) } }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Папка привязана

    private func folderSection(_ folder: APIClient.DirectoryProjectDocs.FolderRef) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            // Фильтр по дате правки — НАД папкой (владелец 05.10.2026:
            // «не под папкой, а над папкой»). Он относится к списку
            // документов, поэтому показывается вместе с ним — в свёрнутой
            // папке остаётся одна строка с названием и числом.
            if docsExpanded && !(docs?.notes ?? []).isEmpty {
                Picker("Обновлены", selection: $dateFilter) {
                    ForEach(NotesDateFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, TFSpacing.xs)
            }

            // Строка папки — раскрывашка, а не переход: тап сворачивает
            // документы в папку и обратно (владелец 05.10.2026). Шеврон
            // поворачивается вниз, когда документы открыты; системный вид, без
            // своих подложек и рамок.
            Button {
                withAnimation(.snappy(duration: 0.2)) { docsExpanded.toggle() }
                TaskCardDisclosureState.saveFlag(docsExpanded, key: docsExpandedKey)
            } label: {
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: "folder")
                        .tfText(.title)
                        .foregroundStyle(Color.tfSub)
                    Text(folder.name)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                    Spacer()
                    Text("\(filteredNotes.count)")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                    Image(systemName: "chevron.right")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .rotationEffect(.degrees(docsExpanded ? 90 : 0))
                }
                .frame(minHeight: 42)
            }
            .buttonStyle(TFTapRowStyle())
            .accessibilityIdentifier("projectDocsFolder")
            .accessibilityLabel(folder.name)
            .accessibilityValue(docsExpanded ? "развёрнуто" : "свёрнуто")
            .accessibilityHint("Свернуть или развернуть документы")

            if docsExpanded {
                folderDocuments
            }
        }
    }

    /// Документы папки: список заметок и «Открепить папку». Живут только в
    /// развёрнутом виде — свёрнутая папка показывает одну строку с названием
    /// и числом документов.
    @ViewBuilder
    private var folderDocuments: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            if filteredNotes.isEmpty {
                Text(filteredNotesHint)
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                    .padding(.leading, TFSpacing.lg)
            }

            if let rootID = docs?.folder?.id, let folders = docs?.folders {
                // Дерево: проект → папки задач → файлы. Папки идут первыми
                // (свежие сверху), заметки прямо в корне — после них.
                ForEach(subfolders(of: rootID, in: folders)) { f in
                    folderBlock(f, all: folders, depth: 0)
                }
                ForEach(filteredNotes.filter { $0.folderId == rootID || $0.folderId == nil }) { note in
                    noteRow(note, indent: TFSpacing.lg)
                }
            } else {
                ForEach(filteredNotes) { note in
                    noteRow(note, indent: TFSpacing.lg)
                }
            }

            Button("Открепить папку") { detachConfirm = true }
                .buttonStyle(TFTapRowStyle())
                .tfText(.action)
                .foregroundStyle(Color.tfDim)
                .padding(.top, TFSpacing.xs)
        }
    }

    private func noteRow(_ note: APIClient.DirectoryProjectDocs.NoteRef, indent: CGFloat) -> some View {
        Button { pendingNoteID = note.id } label: {
            HStack(alignment: .top, spacing: TFSpacing.sm) {
                Image(systemName: "doc.text")
                    .tfText(.input)
                    .foregroundStyle(Color.tfDim)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "Без названия" : note.title)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                    Text(updatedLabel(for: note))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.leading, indent)
            .frame(minHeight: 42)
        }
        .buttonStyle(TFTapRowStyle())
    }

    /// Подпапки, у которых после фильтра по дате есть документы; свежие сверху.
    private func subfolders(of parent: Int, in all: [APIClient.DirectoryProjectDocs.FolderNode]) -> [APIClient.DirectoryProjectDocs.FolderNode] {
        let kids = all.filter { $0.parentId == parent && subtreeNotes($0.id, in: all).isEmpty == false }
        func newest(_ f: APIClient.DirectoryProjectDocs.FolderNode) -> Date {
            subtreeNotes(f.id, in: all).compactMap { $0.updatedAt.flatMap(DateFormats.sqliteUTC) }.max() ?? .distantPast
        }
        return kids.sorted { newest($0) > newest($1) }
    }

    /// Все (отфильтрованные) заметки папки и её потомков.
    private func subtreeNotes(_ id: Int, in all: [APIClient.DirectoryProjectDocs.FolderNode]) -> [APIClient.DirectoryProjectDocs.NoteRef] {
        var ids: Set<Int> = [id]
        var grew = true
        while grew {
            grew = false
            for f in all where f.parentId != nil && ids.contains(f.parentId!) && !ids.contains(f.id) {
                ids.insert(f.id); grew = true
            }
        }
        return filteredNotes.filter { $0.folderId.map(ids.contains) ?? false }
    }

    /// Строка папки задачи; по тапу раскрывается (файлы и вложенные папки).
    private func folderBlock(_ f: APIClient.DirectoryProjectDocs.FolderNode, all: [APIClient.DirectoryProjectDocs.FolderNode], depth: Int) -> AnyView {
        let isOpen = openFolders.contains(f.id)
        let pad = TFSpacing.lg + CGFloat(depth) * TFSpacing.md
        return AnyView(
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isOpen { openFolders.remove(f.id) } else { openFolders.insert(f.id) }
                    }
                } label: {
                    HStack(spacing: TFSpacing.sm) {
                        Image(systemName: "folder")
                            .tfText(.input)
                            .foregroundStyle(Color.tfSub)
                        Text(f.name.isEmpty ? "Без названия" : f.name)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                            .lineLimit(1)
                        Spacer()
                        Text("\(subtreeNotes(f.id, in: all).count)")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfDim)
                        Image(systemName: "chevron.right")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .padding(.leading, pad)
                    .frame(minHeight: 42)
                }
                .buttonStyle(TFTapRowStyle())
                .accessibilityLabel(f.name)
                .accessibilityValue(isOpen ? "развёрнуто" : "свёрнуто")
                if isOpen {
                    ForEach(subfolders(of: f.id, in: all)) { child in
                        folderBlock(child, all: all, depth: depth + 1)
                    }
                    ForEach(filteredNotes.filter { $0.folderId == f.id }) { note in
                        noteRow(note, indent: pad + TFSpacing.lg)
                    }
                }
            }
        )
    }

    /// Заметки, отфильтрованные по выбранному `dateFilter`. Если фильтр
    /// режет всё — список пустой; для `Picker`'а показываем подсказку.
    private var filteredNotes: [APIClient.DirectoryProjectDocs.NoteRef] {
        let all = docs?.notes ?? []
        guard let cutoff = dateFilter.cutoff(now: Date()) else { return all }
        return all.filter { note in
            guard let updated = note.updatedAt.flatMap(DateFormats.sqliteUTC) else {
                return false
            }
            return updated >= cutoff
        }
    }

    /// Текст-подсказка под пустым списком после фильтра.
    private var filteredNotesHint: String {
        switch dateFilter {
        case .day: return "За последние сутки ничего не правилось"
        case .week: return "За последнюю неделю ничего не правилось"
        case .month: return "За последний месяц ничего не правилось"
        case .all: return "В папке пока нет заметок"
        }
    }

    /// Подпись под названием: «обновлено 11.09.2026» или «никогда» —
    /// короткая, в одну строку, не вытесняет название.
    private func updatedLabel(for note: APIClient.DirectoryProjectDocs.NoteRef) -> String {
        guard let updated = note.updatedAt.flatMap(DateFormats.sqliteUTC) else {
            return "никогда"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return "обновлено " + f.string(from: updated)
    }

    // MARK: - Папка не привязана

    private var emptySection: some View {
        TFCard {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                Text("Прикрепите папку документов — вся документация по проекту будет здесь же, рядом с задачами. Папка живёт в Базе знаний, так что документы можно перетаскивать и открывать оттуда.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                HStack(spacing: TFSpacing.sm) {
                    Button {
                        Task { await createAndAttach() }
                    } label: {
                        HStack(spacing: TFSpacing.sm) {
                            Image(systemName: "folder.badge.plus").tfTypeFont(size: 16)
                            Text(busy ? "Создаём…" : "Создать «\(project.name)»")
                        }
                        .tfText(.action)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tfText)
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(height: TFHitTarget.min)
                        .background(Color.tfCard2)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .disabled(busy)

                    if !allFolders.isEmpty {
                        Button {
                            pickerOpen = true
                        } label: {
                            HStack(spacing: TFSpacing.sm) {
                                Image(systemName: "folder").tfTypeFont(size: 16)
                                Text("Выбрать папку")
                            }
                            .tfText(.action)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tfText)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: TFHitTarget.min)
                            .background(Color.tfCard2)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                        }
                        .buttonStyle(TFTapScaleStyle())
                    }
                }
            }
        }
    }

    // MARK: - Действия

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let docsResult = apiClient.directoryProjectDocs(projectId: project.id)
        async let foldersResult = apiClient.journalFolders()
        do {
            docs = try await docsResult
            allFolders = (try? await foldersResult) ?? []
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось загрузить документацию"
        }
    }

    private func createAndAttach() async {
        busy = true
        defer { busy = false }
        do {
            let folder = try await apiClient.createJournalFolder(name: project.name)
            let updated = try await apiClient.patchProject(id: project.id, fields: ["notes_folder_id": .number(Double(folder.id))])
            onProjectPatched(updated)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать папку"
        }
    }

    private func attach(_ folderId: Int) async {
        do {
            let updated = try await apiClient.patchProject(id: project.id, fields: ["notes_folder_id": .number(Double(folderId))])
            onProjectPatched(updated)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось привязать папку"
        }
    }

    private func detach() async {
        do {
            let updated = try await apiClient.patchProject(id: project.id, fields: ["notes_folder_id": JSONValue.null])
            onProjectPatched(updated)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось открепить папку"
        }
    }

    private func addNote() async {
        guard let folderId = docs?.folder?.id else { return }
        do {
            let note = try await apiClient.createNote(folderId: folderId, content: .string(""))
            await load()
            pendingNoteID = note.id
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать заметку"
        }
    }
}
