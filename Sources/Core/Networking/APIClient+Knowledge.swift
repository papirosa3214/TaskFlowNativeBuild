import Foundation

public extension APIClient {

    func knowledgeDatasets(includeDisabled: Bool = false) async throws -> [ApiKnowledgeDataset] {
        struct Response: Decodable {
            let datasets: [ApiKnowledgeDataset]
            let defaultDatasetId: String?
            enum CodingKeys: String, CodingKey {
                case datasets
                case defaultDatasetId = "default_dataset_id"
            }
        }
        let response: Response = try await request(
            .get, "/knowledge/datasets",
            query: includeDisabled ? [URLQueryItem(name: "include_disabled", value: "1")] : []
        )
        return response.datasets
    }

    // ── Прошлый ответ для первого кадра ────────────────────────────────────
    // Владелец (10.11.2026): «Почему так долго грузится?… не может
    // сохраниться снимок того, сколько документов здесь находится». Поэтому
    // экран сначала рисует прошлый ответ из `ResponseCache`, а свежий
    // приходит следом и обновляет счётчики.

    func cachedKnowledgeDatasets(includeDisabled: Bool = true) -> [ApiKnowledgeDataset]? {
        struct Response: Decodable { let datasets: [ApiKnowledgeDataset] }
        return cached(
            Response.self, "/knowledge/datasets",
            query: includeDisabled ? [URLQueryItem(name: "include_disabled", value: "1")] : []
        )?.datasets
    }

    func cachedKnowledgeSections() -> [KnowledgeSection]? {
        struct Response: Decodable { let sections: [KnowledgeSection] }
        return cached(Response.self, "/knowledge/sections")?.sections
    }

    func cachedKnowledgeDatasetDocuments(
        datasetId: String, page: Int = 1, pageSize: Int = 50
    ) -> [ApiKnowledgeDocument]? {
        struct Response: Decodable { let documents: [ApiKnowledgeDocument] }
        return cached(
            Response.self, "/knowledge/datasets/\(datasetId)/documents",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )?.documents
    }

    // ── Управление датасетами и разделами (владелец 09.11.2026) ────────────
    // Решения принимает сервер: `enabled`, раздел и доступы ролей живут в его
    // реестре, телефон только передаёт выбор.

    func knowledgeSections() async throws -> [KnowledgeSection] {
        struct Response: Decodable { let sections: [KnowledgeSection] }
        let response: Response = try await request(.get, "/knowledge/sections")
        return response.sections
    }

    func createKnowledgeSection(title: String) async throws -> KnowledgeSection {
        struct Response: Decodable { let section: KnowledgeSection }
        let response: Response = try await request(
            .post, "/knowledge/sections", body: ["title": JSONValue.string(title)]
        )
        return response.section
    }

    func renameKnowledgeSection(id: Int, title: String) async throws {
        let _: APIOkResponse = try await request(
            .patch, "/knowledge/sections/\(id)", body: ["title": JSONValue.string(title)]
        )
    }

    func moveKnowledgeSection(id: Int, position: Int) async throws {
        let _: APIOkResponse = try await request(
            .patch, "/knowledge/sections/\(id)", body: ["position": JSONValue.number(Double(position))]
        )
    }

    func deleteKnowledgeSection(id: Int) async throws {
        let _: APIOkResponse = try await request(.delete, "/knowledge/sections/\(id)")
    }

    /// Включить/исключить датасет, перенести в раздел, переименовать.
    /// `sectionId == nil` при `clearSection == true` — «без раздела».
    func updateKnowledgeDataset(
        id: String,
        enabled: Bool? = nil,
        sectionId: Int? = nil,
        clearSection: Bool = false,
        title: String? = nil
    ) async throws {
        var body: [String: JSONValue] = [:]
        if let enabled { body["enabled"] = .bool(enabled) }
        if clearSection { body["section_id"] = .null }
        else if let sectionId { body["section_id"] = .number(Double(sectionId)) }
        if let title { body["title"] = .string(title) }
        let _: APIOkResponse = try await request(.patch, "/knowledge/datasets/\(id)", body: body)
    }

    /// Выдать датасет ролям целым набором: что не перечислено — доступа нет.
    func setKnowledgeDatasetRoles(datasetId: String, roleKeys: [String]) async throws -> [KnowledgeRole] {
        struct Response: Decodable { let roles: [KnowledgeRole] }
        let response: Response = try await request(
            .put, "/knowledge/datasets/\(datasetId)/roles",
            body: ["role_keys": JSONValue.array(roleKeys.map(JSONValue.string))]
        )
        return response.roles
    }

    func createKnowledgeDataset(name: String) async throws -> ApiKnowledgeDataset {
        struct Response: Decodable { let id: String; let name: String }
        let response: Response = try await request(
            .post, "/knowledge/datasets", body: ["name": JSONValue.string(name)]
        )
        return ApiKnowledgeDataset(
            id: response.id, name: response.name, documentCount: 0, isDefault: false
        )
    }

    /// `datasetIds` пустой — сервер ищет по всем включённым датасетам
    /// (владелец: «обычное окно ввода поисковое, стандартное… если хочу не
    /// везде искать, проваливаюсь в конкретный датасет»).
    func knowledgeSearch(
        query: String, topK: Int = 8, datasetIds: [String] = []
    ) async throws -> [ApiKnowledgeChunk] {
        struct Response: Decodable { let results: [ApiKnowledgeChunk] }
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "top_k", value: String(topK)),
        ]
        if !datasetIds.isEmpty {
            items.append(URLQueryItem(name: "dataset_id", value: datasetIds.joined(separator: ",")))
        }
        let response: Response = try await request(.get, "/knowledge/search", query: items)
        return response.results
    }

    /// Документы одного датасета — экран датасета. `datasetId` обязателен:
    /// «показать всё сразу» смешало бы тематики, а владелец просил обратное.
    func knowledgeDatasetDocuments(
        datasetId: String, page: Int = 1, pageSize: Int = 50
    ) async throws -> [ApiKnowledgeDocument] {
        struct Response: Decodable { let documents: [ApiKnowledgeDocument] }
        let response: Response = try await request(
            .get, "/knowledge/datasets/\(datasetId)/documents",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )
        return response.documents
    }

    /// Загрузка файла в датасет. Байты идут как есть — сервер сам ставит
    /// документ на разбор и отвечает его идентификатором.
    func uploadKnowledgeDocument(
        datasetId: String, name: String, data: Data, mime: String
    ) async throws -> KnowledgeDocumentStatus {
        struct Response: Decodable {
            let ragflowId: String
            let name: String
            enum CodingKeys: String, CodingKey { case ragflowId = "ragflow_id", name }
        }
        let response: Response = try await uploadRaw(
            path: "/knowledge/datasets/\(datasetId)/documents",
            query: [URLQueryItem(name: "name", value: name)],
            data: data,
            mime: mime
        )
        return KnowledgeDocumentStatus(
            id: response.ragflowId, name: response.name,
            run: "RUNNING", progress: nil, message: nil, chunkCount: nil
        )
    }

    /// Ход разбора: приложение спрашивает, пока документ не готов.
    func knowledgeDocumentStatus(
        datasetId: String, ragflowId: String
    ) async throws -> KnowledgeDocumentStatus {
        try await request(
            .get, "/knowledge/documents/\(ragflowId)/status",
            query: [URLQueryItem(name: "dataset_id", value: datasetId)]
        )
    }

    func deleteKnowledgeDocument(datasetId: String, ragflowId: String) async throws {
        let _: APIOkResponse = try await request(
            .delete, "/knowledge/documents/\(ragflowId)",
            query: [URLQueryItem(name: "dataset_id", value: datasetId)]
        )
    }

    func reparseKnowledgeDocuments(datasetId: String, documentIds: [String]) async throws {
        let _: APIOkResponse = try await request(
            .post, "/knowledge/datasets/\(datasetId)/documents/reparse",
            body: ["document_ids": JSONValue.array(documentIds.map(JSONValue.string))]
        )
    }

    /// Ответ по выбранным датасетам: модель сервера формулирует текст, куски
    /// возвращаются источниками. `datasetIds` не бывает пустым — «по всему
    /// сразу» подмешало бы чужие тематики.
    func knowledgeAsk(
        question: String, datasetIds: [String], documentIds: [String] = []
    ) async throws -> KnowledgeAnswer {
        var body: [String: JSONValue] = [
            "question": .string(question),
            "dataset_ids": .array(datasetIds.map(JSONValue.string)),
        ]
        if !documentIds.isEmpty { body["document_ids"] = .array(documentIds.map(JSONValue.string)) }
        return try await request(.post, "/knowledge/ask", body: body, timeout: 120)
    }

    /// Что вообще лежит в базе знаний — включая документы проектов, которых
    /// в TaskFlow уже нет: удаление проекта индекс не трогает, и это и есть
    /// архив.
    func knowledgeDocuments(page: Int = 1, pageSize: Int = 50) async throws -> [ApiKnowledgeDocument] {
        struct Response: Decodable { let documents: [ApiKnowledgeDocument] }
        let response: Response = try await request(
            .get, "/knowledge/documents",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )
        return response.documents
    }
}
