import Foundation
import Observation

/// Стор проектов — загрузка + кэш в памяти. Проекты меняются редко
/// относительно задач, поэтому без точечной оптимистики: правки ждут ответа
/// сервера (spec §8 — так делает и веб для не-drag&drop мутаций).
@MainActor
@Observable
public final class ProjectStore {
    public private(set) var projects: [ApiProject] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            projects = try await apiClient.projects()
        } catch is CancellationError {
            // Отмена при уходе с экрана не является ошибкой загрузки.
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    public func create(
        name: String,
        color: String? = nil,
        withDocs: Bool = false,
        knowledgeDatasetId: String? = nil
    ) async -> ApiProject? {
        do {
            let created = try await apiClient.createProject(
                name: name, color: color, withDocs: withDocs,
                knowledgeDatasetId: knowledgeDatasetId
            )
            projects.append(created)
            return created
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    public private(set) var archivedProjects: [ApiProject] = []
    public var archiveErrorMessage: String?

    public func loadArchive() async {
        archiveErrorMessage = nil
        do { archivedProjects = try await apiClient.archivedProjects() }
        catch is CancellationError {}
        catch { archiveErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    @discardableResult
    public func restoreArchived(projectId: String) async -> Bool {
        do {
            try await apiClient.restoreProject(id: projectId)
            await load()
            await loadArchive()
            return true
        } catch { archiveErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription; return false }
    }

    @discardableResult
    public func purgeArchived(projectId: String) async -> Bool {
        guard archivedProjects.contains(where: { $0.id == projectId }) else {
            archiveErrorMessage = "Окончательное удаление доступно только из архива."
            return false
        }
        do {
            try await apiClient.permanentlyDeleteProject(id: projectId)
            await loadArchive()
            return true
        } catch { archiveErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription; return false }
    }

    public func delete(projectId: String) async {
        let snapshot = projects
        projects.removeAll { $0.id == projectId }
        do {
            try await apiClient.deleteProject(id: projectId)
            await loadArchive()
        } catch {
            projects = snapshot
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
