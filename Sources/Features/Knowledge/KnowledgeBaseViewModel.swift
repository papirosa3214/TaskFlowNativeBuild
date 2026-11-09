import Foundation
import Observation

/// Список датасетов базы знаний: полки по разделам, включение/исключение,
/// доступ ролям.
///
/// Решает сервер — здесь только состояние экрана и отправка выбора. Телефон
/// не держит собственного списка датасетов: после каждого решения он
/// перечитывает ответ сервера, иначе «исключил, а оно на месте» (правило
/// тонкого клиента, 09.11.2026).
@MainActor
@Observable
public final class KnowledgeBaseViewModel {
    private let api = APIClient()

    public private(set) var datasets: [ApiKnowledgeDataset] = []
    public private(set) var sections: [KnowledgeSection] = []
    public private(set) var roles: [KnowledgeRole] = []
    public var includeDisabled = false
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    /// Поиск по базе: пустой запрос — полки, непустой — найденные фрагменты.
    public private(set) var searchResults: [ApiKnowledgeChunk] = []
    public private(set) var isSearching = false
    /// Запрос, по которому пришли `searchResults`: пока он не совпал с тем,
    /// что в поле ввода, результаты не показываем (гонка дебаунса).
    private var searchedQuery = ""

    public init() {}

    /// Полки для экрана: разделы владельца в его порядке, «Без раздела» в
    /// конце. Исключённые датасеты в полки не попадают.
    public var shelves: [KnowledgeShelf] {
        KnowledgeLibrary.shelves(
            datasets: datasets.map {
                KnowledgeDatasetRef(id: $0.id, sectionId: $0.section?.id, enabled: $0.isEnabled)
            },
            sections: sections
        )
    }

    public func datasets(on shelf: KnowledgeShelf) -> [ApiKnowledgeDataset] {
        shelf.datasetIds.compactMap { id in datasets.first { $0.id == id } }
    }

    /// Датасеты, которые владелец исключил — показываются только по его
    /// просьбе («Показать исключённые»): по умолчанию их для базы знаний нет.
    public var disabledDatasets: [ApiKnowledgeDataset] {
        datasets.filter { !$0.isEnabled }
    }

    /// Поиск по базе с верхнего экрана: область — включённые датасеты (их
    /// выбирает сервер, когда `dataset_id` не передан). Короткий ввод не
    /// отправляем: retrieval на односложные запросы отдаёт случайные куски.
    public func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchedQuery = trimmed
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await api.knowledgeSearch(query: trimmed, topK: 20)
            searchedQuery = trimmed
            searchResults = found
            errorMessage = nil
        } catch {
            searchedQuery = trimmed
            searchResults = []
            errorMessage = error.localizedDescription
        }
    }

    /// Результаты отдаём только для того запроса, который сейчас в поле.
    public func results(for text: String) -> [ApiKnowledgeChunk] {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == searchedQuery ? searchResults : []
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let datasetsTask = api.knowledgeDatasets(includeDisabled: true)
            async let sectionsTask = api.knowledgeSections()
            let (loadedDatasets, loadedSections) = try await (datasetsTask, sectionsTask)
            datasets = loadedDatasets
            sections = loadedSections
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await loadRoles()
    }

    /// Роли нужны только для окна доступов; их отсутствие не должно гасить
    /// сам список датасетов.
    private func loadRoles() async {
        guard roles.isEmpty else { return }
        do {
            roles = try await api.roles().map { KnowledgeRole(key: $0.role, title: $0.title) }
        } catch {
            roles = []
        }
    }

    public func setEnabled(_ dataset: ApiKnowledgeDataset, _ enabled: Bool) async {
        await mutate { try await api.updateKnowledgeDataset(id: dataset.id, enabled: enabled) }
    }

    public func setSection(_ dataset: ApiKnowledgeDataset, _ sectionId: Int?) async {
        await mutate {
            try await api.updateKnowledgeDataset(
                id: dataset.id, sectionId: sectionId, clearSection: sectionId == nil
            )
        }
    }

    public func setRoles(_ dataset: ApiKnowledgeDataset, keys: [String]) async {
        await mutate {
            _ = try await api.setKnowledgeDatasetRoles(datasetId: dataset.id, roleKeys: keys)
        }
    }

    @discardableResult
    public func createSection(_ title: String) async -> KnowledgeSection? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let section = try await api.createKnowledgeSection(title: name)
            sections.append(section)
            return section
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func renameSection(_ section: KnowledgeSection, title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await mutate { try await api.renameKnowledgeSection(id: section.id, title: name) }
    }

    public func deleteSection(_ section: KnowledgeSection) async {
        await mutate { try await api.deleteKnowledgeSection(id: section.id) }
    }

    /// Одно решение владельца → перечитать список. Перечитывать дешевле, чем
    /// повторять правила сервера на телефоне (порядок полок, чей датасет,
    /// пустые разделы).
    private func mutate(_ action: () async throws -> Void) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await action()
            datasets = try await api.knowledgeDatasets(includeDisabled: true)
            sections = try await api.knowledgeSections()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
