import SwiftUI

/// «База знаний» с 09.11.2026 — не дневник, а полки датасетов RAGFlow.
///
/// Владелец (09.11.2026): «должен видеть дата-сеты, базы данных, окно
/// запросов», «добавлять или исключать эти датасеты прямо через мобильное
/// приложение», «там есть дата-сеты по тематикам», «устанавливать доступы
/// агентам». Поэтому на первом экране: разделы с датасетами, строка «Спросить
/// базу» и вход в дневник заметок — заметки остались одной из полок, а не
/// всем экраном.
public struct KnowledgeBaseScreen: View {
    @State private var viewModel = KnowledgeBaseViewModel()
    @State private var sectionEditor: SectionEditorState?
    @State private var rolesEditor: ApiKnowledgeDataset?
    @State private var pendingDeletion: ApiKnowledgeDataset?
    @State private var pendingSectionDeletion: KnowledgeSection?
    @State private var query = ""
    @State private var isAskOpen = false
    @State private var askQuestion = ""

    public init() {}

    public var body: some View {
        List {
            if viewModel.errorMessage != nil {
                Section {
                    TFErrorBanner(viewModel.errorMessage, variant: .block)
                        .knowledgeRow()
                }
            }

            if viewModel.isLoading && viewModel.datasets.isEmpty {
                Section { TFLoading(.block).frame(maxWidth: .infinity).knowledgeRow() }
            } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults
            } else {
                ForEach(viewModel.shelves) { shelf in
                    shelfView(shelf)
                }
                if !viewModel.disabledDatasets.isEmpty {
                    disabledShelf
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(TFSpacing.xs)
        .tfScreenBackground()
        .tint(Color.tfText)
        .refreshable { await viewModel.load() }
        .tfNativeHeader("База знаний", displayMode: .large)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Поиск по базе знаний"
        )
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await viewModel.search("")
                return
            }
            // Пауза на ввод: без неё каждый символ — отдельный retrieval по
            // всей базе (владелец, 10.11.2026: «долго грузится»).
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search(trimmed)
        }
        .task { await viewModel.load() }
        .toolbar { toolbarContent }
        .tfSheet(isPresented: $isAskOpen) {
            KnowledgeAskSheet(
                datasets: viewModel.datasets.filter(\.isEnabled),
                preselecting: nil,
                initialQuestion: askQuestion
            )
        }
        .tfSheet(item: $sectionEditor) { state in
            KnowledgeSectionEditorSheet(state: state) { title in
                guard let title else { return }
                if let section = state.section {
                    await viewModel.renameSection(section, title: title)
                } else {
                    await viewModel.createSection(title)
                }
            }
        }
        .tfSheet(item: $rolesEditor) { dataset in
            KnowledgeRolesSheet(
                dataset: dataset,
                roles: viewModel.roles
            ) { keys in
                await viewModel.setRoles(dataset, keys: keys)
            }
        }
        .confirmationDialog(
            "Удалить раздел «\(pendingSectionDeletion?.title ?? "")»?",
            isPresented: Binding(
                get: { pendingSectionDeletion != nil },
                set: { if !$0 { pendingSectionDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить раздел", role: .destructive) {
                if let section = pendingSectionDeletion {
                    pendingSectionDeletion = nil
                    Task { await viewModel.deleteSection(section) }
                }
            }
        } message: {
            Text("Датасеты останутся: они просто окажутся в «Без раздела».")
        }
        .confirmationDialog(
            "Исключить датасет «\(pendingDeletion?.name ?? "")»?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Исключить из поиска", role: .destructive) {
                if let dataset = pendingDeletion {
                    pendingDeletion = nil
                    Task { await viewModel.setEnabled(dataset, false) }
                }
            }
        } message: {
            Text("Датасет пропадёт из поиска — и вашего, и ролей. Документы в RAGFlow останутся.")
        }
    }

    // ── Строки экрана ──────────────────────────────────────────────────────

    /// Найденные фрагменты: карточка сверху — «спросить по этому запросу»,
    /// ниже сами куски с названием документа. Действий с куском нет:
    /// открывать из индекса нечего, оригинал живёт в своём приложении.
    @ViewBuilder
    private var searchResults: some View {
        let found = viewModel.results(for: query)
        let ask = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Section {
            KnowledgeRimButton(title: "Спросить базу", systemImage: "text.magnifyingglass") {
                askQuestion = ask
                isAskOpen = true
            }
            .knowledgeRow()
            .listRowInsets(EdgeInsets(top: TFSpacing.xs, leading: TFSpacing.sm, bottom: TFSpacing.xs, trailing: TFSpacing.sm))
            if viewModel.isSearching && found.isEmpty {
                TFLoading(.inline).frame(maxWidth: .infinity).knowledgeRow()
            } else if found.isEmpty {
                Text("Ничего не нашлось. Попробуйте другие слова — поиск смысловой, а не по точному совпадению.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .knowledgeRow()
            } else {
                ForEach(found) { chunk in
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text(chunk.title?.isEmpty == false ? chunk.title! : chunk.documentName)
                                .tfText(.body)
                                .foregroundStyle(Color.tfText)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "text.quote")
                                .foregroundStyle(Color.tfSub)
                        }
                        Text(chunk.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(3)
                    }
                    .listRowInsets(EdgeInsets(top: TFSpacing.sm, leading: TFSpacing.sm, bottom: TFSpacing.sm, trailing: TFSpacing.sm))
                    .knowledgeRow()
                }
            }
        } header: {
            if !found.isEmpty {
                Text("Найдено: \(found.count)")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
        }
    }

    private func shelfView(_ shelf: KnowledgeShelf) -> some View {
        let datasets = viewModel.datasets(on: shelf)
        return Section {
            if datasets.isEmpty {
                if shelf.sectionId == nil {
                    Text("Раздел пуст — перенесите сюда датасет.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .knowledgeRow()
                        .hintAnchor(HintAnchorID.knowledgeUnsorted)
                } else {
                    Text("Раздел пуст — перенесите сюда датасет.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .knowledgeRow()
                }
            } else {
                ForEach(Array(datasets.enumerated()), id: \.element.id) { index, dataset in
                    if shelf.sectionId == nil && index == 0 {
                        datasetRow(dataset)
                            .hintAnchor(HintAnchorID.knowledgeUnsorted)
                    } else {
                        datasetRow(dataset)
                    }
                }
            }
        } header: {
            if shelf.sectionId != nil {
                HStack(spacing: TFSpacing.sm) {
                    Text(shelf.title)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                    Spacer(minLength: 0)
                    if let section = viewModel.sections.first(where: { $0.id == shelf.sectionId }) {
                        Menu {
                            Button("Переименовать", systemImage: "pencil") {
                                sectionEditor = SectionEditorState(section: section, title: section.title)
                            }
                            Button("Удалить раздел", systemImage: "trash", role: .destructive) {
                                pendingSectionDeletion = section
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(Color.tfText)
                        }
                        .accessibilityLabel("Раздел \(shelf.title)")
                    }
                }
                .hintAnchor(HintAnchorID.knowledgeShelves)
            }
        }
    }

    private func datasetRow(_ dataset: ApiKnowledgeDataset) -> some View {
        NavigationLink {
            KnowledgeDatasetScreen(dataset: dataset)
        } label: {
            datasetLabel(dataset, subtitle: subtitle(for: dataset))
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .listRowInsets(EdgeInsets(top: TFSpacing.xs, leading: TFSpacing.sm, bottom: TFSpacing.xs, trailing: TFSpacing.sm))
        .knowledgeRow()
        .contextMenu { datasetMenu(dataset) }
    }

    private func datasetLabel(_ dataset: ApiKnowledgeDataset, subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(dataset.name)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: dataset.isTaskflowOwned ? "doc.text" : "externaldrive")
                .foregroundStyle(Color.tfSub)
        }
    }

    private func subtitle(for dataset: ApiKnowledgeDataset) -> String {
        var parts: [String] = []
        if let documents = dataset.documentCount { parts.append("\(documents) док.") }
        if let chunks = dataset.chunkCount { parts.append("\(chunks) фрагм.") }
        if !dataset.roleTitles.isEmpty { parts.append(dataset.roleTitles.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func datasetMenu(_ dataset: ApiKnowledgeDataset) -> some View {
        if dataset.isEnabled {
            Button("Исключить из поиска", role: .destructive) { pendingDeletion = dataset }
        } else {
            Button("Вернуть в поиск") { Task { await viewModel.setEnabled(dataset, true) } }
        }

        Menu("Раздел") {
            Button("Без раздела") { Task { await viewModel.setSection(dataset, nil) } }
            ForEach(viewModel.sections) { section in
                Button(section.title) { Task { await viewModel.setSection(dataset, section.id) } }
            }
        }

        Button("Доступ ролям") { rolesEditor = dataset }
    }

    private var disabledShelf: some View {
        Section {
            ForEach(viewModel.disabledDatasets) { dataset in
                HStack(spacing: TFSpacing.sm) {
                    datasetLabel(dataset, subtitle: "Исключён из поиска")
                    KnowledgeRimButton(title: "Вернуть") {
                        Task { await viewModel.setEnabled(dataset, true) }
                    }
                }
                .listRowInsets(EdgeInsets(top: TFSpacing.xs, leading: TFSpacing.sm, bottom: TFSpacing.xs, trailing: TFSpacing.sm))
                .knowledgeRow()
            }
        } header: {
            Text("Исключены из поиска")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
    }

    // ── Меню экрана ────────────────────────────────────────────────────────

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Новый раздел", systemImage: "folder.badge.plus") {
                    sectionEditor = SectionEditorState(section: nil, title: "")
                }
                Divider()
                NavigationLink {
                    routeDestination(.notes)
                } label: {
                    Label("Заметки TaskFlow", systemImage: "book.closed")
                        .foregroundStyle(Color.tfText)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.tfText)
            }
            .accessibilityLabel("Действия базы знаний")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                routeDestination(.notes)
            } label: {
                Image(systemName: "book.closed")
                    .foregroundStyle(Color.tfText)
            }
            .accessibilityLabel("Заметки TaskFlow")
        }
    }
}

/// Состояние шторки раздела: `section == nil` — создание нового.
struct SectionEditorState: Identifiable, Hashable {
    var id: Int { section?.id ?? 0 }
    let section: KnowledgeSection?
    let title: String
}

/// Шторка «название раздела»: системная, закрывается свайпом, кнопок
/// «Готово»/«Закрыть» внизу нет (правило владельца 05.11.2026).
private struct KnowledgeSectionEditorSheet: View {
    let state: SectionEditorState
    let onSubmit: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isSaving = false

    init(state: SectionEditorState, onSubmit: @escaping (String?) async -> Void) {
        self.state = state
        self.onSubmit = onSubmit
        _title = State(initialValue: state.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название раздела", text: $title)
                    .textInputAutocapitalization(.sentences)
                Text("Раздел — это полка датасетов по теме: «Документация», «Код», «Исследования».")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
            .navigationTitle(state.section == nil ? "Новый раздел" : "Название раздела")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        isSaving = true
                        Task {
                            await onSubmit(title)
                            dismiss()
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}

/// Шторка доступов: какие роли видят датасет в поиске. Набор отправляется
/// целиком — что не выбрано, доступа не имеет.
private struct KnowledgeRolesSheet: View {
    let dataset: ApiKnowledgeDataset
    let roles: [KnowledgeRole]
    let onSubmit: ([String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>

    init(dataset: ApiKnowledgeDataset, roles: [KnowledgeRole], onSubmit: @escaping ([String]) async -> Void) {
        self.dataset = dataset
        self.roles = roles
        self.onSubmit = onSubmit
        _selected = State(initialValue: Set((dataset.roles ?? []).map(\.key)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(roles) { role in
                        Button {
                            if selected.contains(role.key) { selected.remove(role.key) }
                            else { selected.insert(role.key) }
                        } label: {
                            HStack {
                                Text(role.title).tfText(.body).foregroundStyle(Color.tfText)
                                Spacer()
                                if selected.contains(role.key) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.tfRed)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Роль ищет только в выданных датасетах. Не отмеченные роли этот датасет не видят — так чужая тематика не засоряет им поиск.")
                        .tfText(.action)
                }
            }
            .navigationTitle(dataset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            await onSubmit(Array(selected))
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Прозрачная кнопка с кромкой. На iOS 26 это системное стекло, раньше —
/// та же подпись без заливки и с тонкой светлой кромкой. Иконка системная.
struct KnowledgeRimButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) { label }
                .buttonStyle(.glass)
        } else {
            Button(action: action) {
                label
                    .padding(.horizontal, TFSpacing.md)
                    .padding(.vertical, TFSpacing.xs)
            }
            .buttonStyle(.plain)
            .overlay {
                RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous)
                    .strokeBorder(Color.tfStroke, lineWidth: TFBorder.width)
            }
        }
    }

    private var label: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .tfText(.action)
        .foregroundStyle(Color.tfText)
    }
}

extension View {
    /// Строка без своей подложки: сквозь неё виден фон экрана.
    func knowledgeRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.tfStroke)
    }
}
