import SwiftUI

// «База знаний» — смысловой поиск по документации всех проектов сразу.
//
// Отличие от «Поиска» (SearchScreen): тот ищет по названиям задач, проектов и
// меток, то есть по тому, КАК что-то названо. Здесь ищется по СОДЕРЖАНИЮ
// документов — «мы это уже где-то разбирали?». За ручкой стоит RAGFlow на .110,
// но приложение об этом не знает: ходит в `/api/knowledge/*` обычным токеном.
//
// Витрина, а не хранилище: правится документ по-прежнему в самой заметке.
// Найденный кусок ведёт в оригинал (`AppRoute.noteEditor` по `doc_id`), а не
// в копию из индекса — индекс отстаёт до ближайшего ночного синка.
struct KnowledgeScreen: View {
    @State private var query = ""
    @State private var chunks: [ApiKnowledgeChunk] = []
    @State private var documents: [ApiKnowledgeDocument] = []
    @State private var isSearching = false
    @State private var isLoadingDocuments = true
    @State private var errorMessage: String?
    @State private var route: AppRoute?

    private let apiClient = APIClient()

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasQuery: Bool { trimmedQuery.count >= 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                if hasQuery {
                    results
                } else {
                    overview
                }
                TFErrorBanner(errorMessage, variant: .block)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("База знаний")
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "О чём искать в документации"
        )
        .navigationDestination(item: $route) { routeDestination($0) }
        // Дебаунс на сам запрос: `.task(id:)` отменяет предыдущий поиск при
        // смене строки — тот же приём, что на экране «Поиск». Пауза здесь
        // длиннее (400мс): каждый запрос считает эмбеддинг на процессоре
        // сервера, дёргать его на каждую букву незачем.
        .task(id: trimmedQuery) {
            guard hasQuery else {
                chunks = []; isSearching = false
                return
            }
            isSearching = true
            errorMessage = nil
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            do {
                chunks = try await apiClient.knowledgeSearch(query: trimmedQuery)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось выполнить поиск"
                chunks = []
            }
            isSearching = false
        }
        .task {
            do {
                documents = try await apiClient.knowledgeDocuments()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось открыть базу знаний"
            }
            isLoadingDocuments = false
        }
    }

    // MARK: - Пустой экран: что вообще лежит в базе

    @ViewBuilder
    private var overview: some View {
        if isLoadingDocuments {
            TFLoading(.block)
        } else if documents.isEmpty {
            TFEmptyState(
                icon: "books.vertical",
                text: "База знаний пуста — документы проектов попадают сюда автоматически, раз в сутки"
            )
        } else {
            let indexed = documents.count { $0.indexed }
            Text("\(documents.count) \(ProjectCard.docWord(documents.count)) в базе"
                 + (indexed < documents.count ? ", индексируется \(documents.count - indexed)" : ""))
                .tfText(.caption)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.xs)
                .padding(.bottom, TFSpacing.xs)

            ForEach(documents) { document in
                documentRow(document)
            }
        }
    }

    private func documentRow(_ document: ApiKnowledgeDocument) -> some View {
        Button {
            if let id = document.docId { route = .noteEditor(noteID: id) }
        } label: {
            TFCard(padding: TFSpacing.md) {
                HStack(spacing: TFSpacing.md) {
                    Image(systemName: "doc.text")
                        .tfText(.input)
                        .foregroundStyle(Color.tfDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title?.isEmpty == false ? document.title! : "Документ без названия")
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                            .lineLimit(2)
                        HStack(spacing: TFSpacing.xs) {
                            if let project = document.project, !project.isEmpty {
                                Text(project)
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfSub)
                                    .lineLimit(1)
                            }
                            if document.archived {
                                Text("архив")
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfDim)
                            }
                            if !document.indexed {
                                Text("индексируется")
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfDim)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(TFTapRowStyle())
    }

    // MARK: - Результаты поиска

    @ViewBuilder
    private var results: some View {
        if isSearching && chunks.isEmpty {
            TFLoading(.block)
        } else if chunks.isEmpty && errorMessage == nil {
            TFEmptyState(
                icon: "magnifyingglass",
                text: "Ничего похожего — в документации проектов про это пока не писали"
            )
        } else {
            ForEach(chunks) { chunk in
                chunkCard(chunk)
            }
        }
    }

    private func chunkCard(_ chunk: ApiKnowledgeChunk) -> some View {
        Button {
            if let id = chunk.docId { route = .noteEditor(noteID: id) }
        } label: {
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    HStack(spacing: TFSpacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chunk.title?.isEmpty == false ? chunk.title! : "Документ проекта")
                                .tfText(.caption)
                                .foregroundStyle(Color.tfText)
                                .lineLimit(1)
                            if let project = chunk.project, !project.isEmpty {
                                Text(project)
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfSub)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if let score = chunk.score {
                            Text(String(format: "%.0f%%", score * 100))
                                .tfText(.caption)
                                .foregroundStyle(Color.tfDim)
                                .monospacedDigit()
                        }
                    }
                    Text(Self.cleaned(chunk.text))
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(TFTapRowStyle())
    }

    /// Кусок может начинаться со служебной YAML-шапки (её кладёт синк) —
    /// в витрине это мусор, режем.
    static func cleaned(_ text: String) -> String {
        var body = text
        if body.hasPrefix("---") {
            let parts = body.components(separatedBy: "\n---")
            if parts.count > 1 {
                body = parts.dropFirst().joined(separator: "\n---")
            }
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
