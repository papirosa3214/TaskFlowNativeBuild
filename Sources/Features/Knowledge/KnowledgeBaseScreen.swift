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
    @State private var isAskOpen = false
    @State private var sectionEditor: SectionEditorState?
    @State private var rolesEditor: ApiKnowledgeDataset?
    @State private var pendingDeletion: ApiKnowledgeDataset?
    @State private var pendingSectionDeletion: KnowledgeSection?
    @State private var showDisabled = false

    public init() {}

    public var body: some View {
        ZStack {
            TFScreenFill()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    TFErrorBanner(viewModel.errorMessage, variant: .block)

                    askRow
                        .padding(.horizontal, TFSpacing.screenHorizontal)

                    if viewModel.isLoading && viewModel.datasets.isEmpty {
                        TFLoading(.block).frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.shelves) { shelf in
                            shelfView(shelf)
                        }
                        if showDisabled {
                            disabledShelf
                        }
                    }
                }
                .padding(.vertical, TFSpacing.lg)
            }
            .refreshable { await viewModel.load() }
        }
        .tfNativeHeader("База знаний", displayMode: .large)
        .task { await viewModel.load() }
        .toolbar { toolbarContent }
        .tfSheet(isPresented: $isAskOpen) {
            KnowledgeAskSheet(
                datasets: viewModel.datasets.filter(\.isEnabled),
                preselecting: nil
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
            Button("Исключить из TaskFlow", role: .destructive) {
                if let dataset = pendingDeletion {
                    pendingDeletion = nil
                    Task { await viewModel.setEnabled(dataset, false) }
                }
            }
        } message: {
            Text("Датасет пропадёт из поиска и станет недоступен ролям. Документы в RAGFlow останутся.")
        }
    }

    // ── Строки экрана ──────────────────────────────────────────────────────

    private var askRow: some View {
        TFCard(padding: 0) {
            TFListRow(
                icon: "text.magnifyingglass",
                iconStyle: .plain,
                title: "Спросить базу",
                subtitle: "Ответ по выбранным датасетам со ссылками на источники"
            ) { isAskOpen = true }
            .hintAnchor(HintAnchorID.knowledgeAsk)
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
                            .tfTypeFont(size: 15)
                            .foregroundStyle(Color.tfSub)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Раздел \(shelf.title)")
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
                                .tfTypeFont(size: 15)
                                .foregroundStyle(Color.tfSub)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                    ),
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
        parts.append(dataset.roleTitles.isEmpty ? "только владелец" : dataset.roleTitles.joined(separator: ", "))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func datasetMenu(_ dataset: ApiKnowledgeDataset) -> some View {
        if dataset.isEnabled {
            Button("Исключить из TaskFlow", role: .destructive) { pendingDeletion = dataset }
        } else {
            Button("Вернуть в TaskFlow") { Task { await viewModel.setEnabled(dataset, true) } }
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
            TFSectionHeader("Исключённые")
                .padding(.horizontal, TFSpacing.screenHorizontal)
            TFCard(padding: 0) {
                if viewModel.disabledDatasets.isEmpty {
                    Text("Исключённых датасетов нет.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .padding(TFSpacing.lg)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.disabledDatasets.enumerated()), id: \.element.id) { index, dataset in
                            HStack(spacing: TFSpacing.md) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dataset.name).tfText(.body).foregroundStyle(Color.tfText)
                                    Text("Для TaskFlow выключен")
                                        .tfText(.action).foregroundStyle(Color.tfSub)
                                }
                                Spacer()
                                Button("Вернуть") { Task { await viewModel.setEnabled(dataset, true) } }
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfRed)
                            }
                            .padding(TFSpacing.lg)
                            if index < viewModel.disabledDatasets.count - 1 { TFDivider() }
                        }
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
                Button("Спросить базу") { isAskOpen = true }
                Button("Новый раздел") { sectionEditor = SectionEditorState(section: nil, title: "") }
                TFToggle(isOn: $showDisabled)
                    .accessibilityLabel("Показать исключённые")
                Divider()
                NavigationLink("Заметки TaskFlow") {
                    routeDestination(.notes)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Действия базы знаний")
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
