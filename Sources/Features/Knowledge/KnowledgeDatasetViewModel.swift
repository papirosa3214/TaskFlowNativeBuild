import Foundation
import Observation

/// Документы одного датасета: что лежит, что разбирается, что сорвалось.
///
/// Загрузка и разбор — серверные: телефон отправляет байты, а ход разбора
/// спрашивает у сервера (`run`: DONE / RUNNING / FAIL). Своего состояния
/// индекса на телефоне нет — иначе «загрузил, а в поиске нет» объяснить нечем.
@MainActor
@Observable
public final class KnowledgeDatasetViewModel {
    private let api = APIClient()
    private let datasetId: String

    public private(set) var documents: [ApiKnowledgeDocument] = []
    /// Ход разбора по `ragflow_id` — только для документов в работе.
    public private(set) var statuses: [String: KnowledgeDocumentStatus] = [:]
    public private(set) var isLoading = false
    public private(set) var isUploading = false
    public private(set) var errorMessage: String?
    public var uploadMessage: String?

    /// Поиск внутри датасета: владелец проваливается сюда именно чтобы
    /// искать не везде, а по этой теме.
    public private(set) var searchResults: [ApiKnowledgeChunk] = []
    public private(set) var isSearching = false
    private var searchedQuery = ""

    public init(datasetId: String) {
        self.datasetId = datasetId
    }

    /// Что ещё не в поиске: разбирается или сорвалось. По этому набору экран
    /// решает, показывать ли полосу хода и опрос статуса.
    public var inProgress: [ApiKnowledgeDocument] {
        documents.filter { !$0.indexed }
    }

    public func status(for document: ApiKnowledgeDocument) -> KnowledgeDocumentStatus? {
        statuses[document.ragflowId]
    }

    public func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchedQuery = trimmed
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        searchedQuery = trimmed
        searchResults = (try? await api.knowledgeSearch(
            query: trimmed, topK: 20, datasetIds: [datasetId]
        )) ?? []
    }

    public func results(for text: String) -> [ApiKnowledgeChunk] {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == searchedQuery ? searchResults : []
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await api.knowledgeDatasetDocuments(datasetId: datasetId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshStatuses()
    }

    /// Один заход по документам в работе. Экран зовёт повторно, пока в
    /// `inProgress` есть разбирающиеся: так видно, когда документ попал в
    /// поиск, без ручного обновления.
    public func refreshStatuses() async {
        let pending = documents.filter { !$0.indexed }
        guard !pending.isEmpty else {
            statuses = [:]
            return
        }
        var updated: [String: KnowledgeDocumentStatus] = [:]
        for document in pending {
            if let status = try? await api.knowledgeDocumentStatus(
                datasetId: datasetId, ragflowId: document.ragflowId
            ) {
                updated[document.ragflowId] = status
            }
        }
        statuses = updated
        if updated.values.contains(where: \.isIndexed) {
            // Документ дошёл до DONE — перечитываем список, чтобы он перестал
            // считаться документом «в работе».
            documents = (try? await api.knowledgeDatasetDocuments(datasetId: datasetId)) ?? documents
        }
    }

    @discardableResult
    public func upload(name: String, data: Data, mime: String) async -> Bool {
        isUploading = true
        defer { isUploading = false }
        do {
            _ = try await api.uploadKnowledgeDocument(
                datasetId: datasetId, name: name, data: data, mime: mime
            )
            uploadMessage = "«\(name)» отправлен на разбор"
            errorMessage = nil
            documents = try await api.knowledgeDatasetDocuments(datasetId: datasetId)
            await refreshStatuses()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func delete(_ document: ApiKnowledgeDocument) async {
        do {
            try await api.deleteKnowledgeDocument(datasetId: datasetId, ragflowId: document.ragflowId)
            documents.removeAll { $0.ragflowId == document.ragflowId }
            statuses[document.ragflowId] = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reparse(_ documents: [ApiKnowledgeDocument]) async {
        guard !documents.isEmpty else { return }
        do {
            try await api.reparseKnowledgeDocuments(
                datasetId: datasetId, documentIds: documents.map(\.ragflowId)
            )
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
