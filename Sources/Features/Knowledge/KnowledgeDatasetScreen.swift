import SwiftUI
import UniformTypeIdentifiers

/// Один датасет: что в нём лежит и как положить туда файл.
///
/// Владелец (09.11.2026): «Могу сам загружать туда документы для ченкования».
/// Поэтому здесь две вещи: список документов с ходом разбора и «Добавить
/// документ». Разбор идёт на сервере — экран лишь спрашивает у него статус,
/// пока документ не попал в поиск.
public struct KnowledgeDatasetScreen: View {
    private let dataset: ApiKnowledgeDataset
    @State private var viewModel: KnowledgeDatasetViewModel
    @State private var isPickingFile = false
    @State private var isAskOpen = false
    @State private var pendingDeletion: ApiKnowledgeDocument?
    @State private var query = ""

    public init(dataset: ApiKnowledgeDataset) {
        self.dataset = dataset
        _viewModel = State(initialValue: KnowledgeDatasetViewModel(datasetId: dataset.id))
    }

    public var body: some View {
        ZStack {
            TFScreenFill()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    TFErrorBanner(viewModel.errorMessage, variant: .block)
                    if let uploadMessage = viewModel.uploadMessage {
                        Text(uploadMessage)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                    }

                    if viewModel.isLoading && viewModel.documents.isEmpty {
                        TFLoading(.block).frame(maxWidth: .infinity)
                    } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResults
                    } else if viewModel.documents.isEmpty {
                        TFEmptyState(
                            icon: "doc.badge.plus",
                            text: "Документов нет\nФайл, положенный сюда, сервер разобьёт на фрагменты и добавит в поиск.",
                            actionTitle: "Добавить документ"
                        ) { isPickingFile = true }
                        .padding(.top, TFSpacing.xl)
                    } else {
                        documentsCard
                    }

                    if !dataset.roleTitles.isEmpty {
                        Text("Доступ ролям: \(dataset.roleTitles.joined(separator: ", "))")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                    }
                }
                .padding(.vertical, TFSpacing.lg)
            }
            .refreshable { await viewModel.load() }
        }
        .tfNativeHeader(dataset.name, displayMode: .inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Поиск по этому датасету"
        )
        .onChange(of: query) { _, value in
            Task { await viewModel.search(value) }
        }
        .task { await viewModel.load() }
        .task(id: viewModel.inProgress.count) {
            // Пока есть документы в работе — спрашиваем сервер, пока они не
            // станут DONE или FAIL. Пауза 2 с: разбор небольшого текста обычно
            // укладывается в первую-вторую попытку.
            guard !viewModel.inProgress.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await viewModel.refreshStatuses()
                if viewModel.inProgress.isEmpty { return }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPickingFile = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Добавить документ")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAskOpen = true
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .accessibilityLabel("Спросить по этому датасету")
            }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.plainText, .pdf, .rtf, .html, .spreadsheet, .presentation, .text],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFile(result) }
        }
        .tfSheet(isPresented: $isAskOpen) {
            KnowledgeAskSheet(datasets: [dataset], preselecting: dataset.id)
        }
        .confirmationDialog(
            "Удалить «\(pendingDeletion?.name ?? "")»?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить документ", role: .destructive) {
                if let document = pendingDeletion {
                    pendingDeletion = nil
                    Task { await viewModel.delete(document) }
                }
            }
        } message: {
            Text("Документ исчезнет из индекса. Если его положил TaskFlow, суточный прогон вернёт его снова.")
        }
    }

    /// Результаты поиска внутри датасета: тот же вид строк, что на экране
    /// базы знаний.
    private var searchResults: some View {
        let found = viewModel.results(for: query)
        return VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if viewModel.isSearching && found.isEmpty {
                TFLoading(.inline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, TFSpacing.lg)
            } else if found.isEmpty {
                Text("В этом датасете ничего не нашлось.")
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

    private var documentsCard: some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.documents.enumerated()), id: \.element.id) { index, document in
                    documentRow(document)
                    if index < viewModel.documents.count - 1 { TFDivider() }
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func documentRow(_ document: ApiKnowledgeDocument) -> some View {
        let status = viewModel.status(for: document)
        return TFListRow(
            icon: document.indexed ? "doc.text" : "clock.arrow.circlepath",
            iconStyle: .plain,
            title: displayTitle(document),
            subtitle: subtitle(for: document, status: status),
            trailing: AnyView(
                    Menu {
                        Button("Разобрать заново") { Task { await viewModel.reparse([document]) } }
                        Button("Удалить", role: .destructive) { pendingDeletion = document }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                ),
            verticalPadding: TFSpacing.xs,
            chevron: .hidden
        )
        .contextMenu {
            Button("Разобрать заново") { Task { await viewModel.reparse([document]) } }
            Button("Удалить", role: .destructive) { pendingDeletion = document }
        }
    }

    /// Имя документа в индексе: у заметок TaskFlow это `taskflow-<uuid>.md`, у
    /// остальных — их собственный файл. Заголовок заметки важнее, но пустая
    /// строка вместо заголовка не должна оставлять строку без названия.
    private func displayTitle(_ document: ApiKnowledgeDocument) -> String {
        if let title = document.title, !title.isEmpty { return title }
        let name = document.name
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    /// Подпись только когда она что-то значит: «в поиске» — это норма, о ней
    /// молчим (владелец: «зачем ты мне это говоришь»).
    private func subtitle(for document: ApiKnowledgeDocument, status: KnowledgeDocumentStatus?) -> String? {
        if let status {
            if status.isFailed {
                return status.message.map { "Разбор сорвался: \($0)" } ?? "Разбор сорвался"
            }
            if status.isIndexed { return nil }
            return "Разбирается — в поиске пока нет"
        }
        return document.indexed ? nil : "Разбирается — в поиске пока нет"
    }

    private func handleFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            await viewModel.upload(
                name: url.lastPathComponent, data: data, mime: Self.mime(for: url)
            )
        } catch {
            viewModel.uploadMessage = error.localizedDescription
        }
    }

    /// Тип файла выбирает сервер по расширению; здесь нужно лишь честно
    /// сказать, что именно отправляется.
    private static func mime(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "text/markdown"
        case "txt": return "text/plain"
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "html", "htm": return "text/html"
        case "csv": return "text/csv"
        default: return "application/octet-stream"
        }
    }
}
