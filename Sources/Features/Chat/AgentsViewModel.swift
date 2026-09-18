import Foundation
import Observation

/// Состояние экрана «Команда» (LOCK-176).
///
/// Было: список `ApiUser` (люди + ИИ-учётки + сервисные личности) и их
/// инфраструктура (executionMode, provider, baseURL, credentialRef, API-токен).
/// Стало: список профилей ролей — исполнитель есть роль, Pi в обычном UI не
/// показывается.
///
/// Источник — `GET /api/roles` (`APIClient.roles()`): он отдаёт и профиль, и
/// текущую задачу роли, чего нет у тонкого `/api/runtime/profiles`.
///
/// Старая механика ApiUser/токена не удалена — она переехала в
/// Settings → Service Accounts (LOCK-181), там у неё свои `ApiUser` и VM.
@MainActor
@Observable
final class AgentsViewModel {
    private(set) var profiles: [RoleProfile] = []
    private(set) var isLoading = false
    var listErrorMessage: String?

    private(set) var isOwner = false

    /// Каталог моделей Pi — нужен только редактору модели роли. Грузится
    /// лениво при первом открытии редактора, один раз на жизнь экрана.
    private(set) var models: [RuntimeModel] = []
    private(set) var modelsLoading = false
    var modelsErrorMessage: String?

    /// Какой ряд сейчас раскрыт — `nil`, если все свёрнуты.
    private(set) var expandedRole: String?

    private let api = APIClient()
    private var pollTask: Task<Void, Never>?

    func configure(currentUser: ApiUser?) {
        isOwner = currentUser?.role == .owner
    }

    /// Жив ли исполнитель — общий признак на список (сервер отдаёт его в
    /// каждом профиле одинаковым). `nil`, пока список не загружен.
    var runtimeReady: Bool? {
        profiles.first?.runtimeReady
    }

    /// Раз в 15с — статус роли и текущая задача живые, как в вебе.
    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.load()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func toggleExpand(_ role: String) {
        expandedRole = (expandedRole == role) ? nil : role
    }

    func isExpanded(_ role: String) -> Bool {
        expandedRole == role
    }

    func load() async {
        if profiles.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            profiles = try await api.roles()
            listErrorMessage = nil
        } catch {
            listErrorMessage = Self.message(for: error)
        }
    }

    func profile(for role: String) -> RoleProfile? {
        profiles.first { $0.role == role }
    }

    // MARK: - Модель роли

    /// Ленивая загрузка каталога моделей для пикера.
    func loadModelsIfNeeded() async {
        guard models.isEmpty, !modelsLoading else { return }
        modelsLoading = true
        modelsErrorMessage = nil
        defer { modelsLoading = false }
        do {
            models = try await api.runtimeModels()
        } catch {
            modelsErrorMessage = Self.message(for: error)
        }
    }

    /// Сохранить primary + упорядоченные fallback роли. Сервер проверит, что
    /// каждая модель есть в каталоге, и вернёт 422 иначе.
    @discardableResult
    func updateModelPolicy(role: String, primary: String, fallbacks: [String]) async -> Bool {
        do {
            _ = try await api.updateRuntimeRouting(role: role, primary: primary, fallbacks: fallbacks)
            await load()
            return true
        } catch {
            listErrorMessage = Self.message(for: error)
            return false
        }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
