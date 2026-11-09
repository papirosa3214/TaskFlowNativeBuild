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
        ZStack {
            TFScreenFill()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    TFErrorBanner(viewModel.errorMessage, variant: .block)

                    if viewModel.isLoading && viewModel.datasets.isEmpty {
                        TFLoading(.block).frame(maxWidth: .infinity)
                    } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResults
                    } else {
                        ForEach(viewModel.shelves) { shelf in
                            shelfView(shelf)
                        }
                        if !viewModel.disabledDatasets.isEmpty {
                            disabledShelf
                        }                    }
                }
                .padding(.vertical, TFSpacing.md)
            }
            .refreshable { await viewModel.load() }
        }
        .tfNativeHeader("База знаний", displayMode: .large)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Поиск по базе знаний"
        )
        .onChange(of: query) { _, value in
            Task { await viewModel.search(value) }
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
    private var searchResults: some View {
        let found = viewModel.results(for: query)
        let ask = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFCard(padding: 0) {
                TFListRow(
                    icon: "text.magnifyingglass",
                    iconStyle: .plain,
                    title: "Спросить базу",
                    subtitle: "Ответ по этому запросу со ссылками на источники",
                    verticalPadding: TFSpacing.sm
                ) {
                    askQuestion = ask
                    isAskOpen = true
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)

            if viewModel.isSearching && found.isEmpty {
                TFLoading(.inline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, TFSpacing.lg)
            } else if found.isEmpty {
                Text("Ничего не нашлось. Попробуйте другие слова — поиск смысловой, а не по точному совпадению.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.top, TFSpacing.sm)
            } else {
                TFSectionHeader("Найдено: \(found.count)")
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(found.enumerated()), id: \.element.id) { index, chunk in
                            TFListRow(
                                icon: "text.quote",
                                iconStyle: .plain,
                                content: AnyView(
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chunk.title?.isEmpty == false
                                             ? chunk.title! : chunk.documentName)
                                            .tfText(.body)
                                            .foregroundStyle(Color.tfText)
                                            .lineLimit(1)
                                        Text(chunk.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                            .tfText(.caption)
                                            .foregroundStyle(Color.tfSub)
                                            .lineLimit(3)
                                    }
                                ),
                                verticalPadding: TFSpacing.sm,
                                chevron: .hidden
                            )
                            if index < found.count - 1 { TFDivider() }
                        }
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
            }
        }
    }

    private func shelfView(_ shelf: KnowledgeShelf) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack {
                TFSectionHeader(shelf.title)
                Spacer()
                if let section = viewModel.sections.first(where: { $0.id == shelf.sectionId }) {
                    Menu {
                        Button("Переименовать") {
                            sectionEditor = SectionEditorState(section: section, title: section.title)
                        }
                        Button("Удалить раздел", role: .destructive) {
                            pendingSectionDeletion = section
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Раздел \(shelf.title)")
                    .padding(.trailing, TFSpacing.xs)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)

            let datasets = viewModel.datasets(on: shelf)
            TFCard(padding: 0) {
                if datasets.isEmpty {
                    Text("Раздел пуст — перенесите сюда датасет.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .padding(TFSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(datasets.enumerated()), id: \.element.id) { index, dataset in
                            datasetRow(dataset)
                            if index < datasets.count - 1 { TFDivider() }
                        }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
        .hintAnchor(shelf.sectionId == nil ? HintAnchorID.knowledgeUnsorted : HintAnchorID.knowledgeShelves)
    }

    private func datasetRow(_ dataset: ApiKnowledgeDataset) -> some View {
        NavigationLink {
            KnowledgeDatasetScreen(dataset: dataset)
        } label: {
            TFListRow(
                icon: dataset.isTaskflowOwned ? "doc.text" : "externaldrive",
                iconStyle: .plain,
                title: dataset.name,
                subtitle: subtitle(for: dataset),
                trailing: AnyView(
                        Menu {
                            datasetMenu(dataset)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    ),
                verticalPadding: TFSpacing.xs,
                chevron: .shown
            )
        }
        .buttonStyle(.plain)
        .contextMenu { datasetMenu(dataset) }
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
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Исключены из поиска")
                .padding(.horizontal, TFSpacing.screenHorizontal)
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.disabledDatasets.enumerated()), id: \.element.id) { index, dataset in
                        TFListRow(
                            icon: dataset.isTaskflowOwned ? "doc.text" : "externaldrive",
                            iconStyle: .plain,
                            title: dataset.name,
                            subtitle: "Исключён из поиска",
                            trailing: AnyView(
                                Button("Вернуть") { Task { await viewModel.setEnabled(dataset, true) } }
                            ),
                            verticalPadding: TFSpacing.xs,
                            chevron: .hidden
                        )
                        if index < viewModel.disabledDatasets.count - 1 { TFDivider() }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    // ── Меню экрана ────────────────────────────────────────────────────────

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Новый раздел") { sectionEditor = SectionEditorState(section: nil, title: "") }
                Divider()
                NavigationLink("Заметки TaskFlow") {
                    routeDestination(.notes)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Действия базы знаний")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                askQuestion = query
                isAskOpen = true
            } label: {
                Image(systemName: "text.magnifyingglass")
            }
            .accessibilityLabel("Спросить базу")
            .hintAnchor(HintAnchorID.knowledgeAsk)
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                routeDestination(.notes)
            } label: {
                Image(systemName: "book")
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
