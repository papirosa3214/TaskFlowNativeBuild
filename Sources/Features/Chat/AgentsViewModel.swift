import Foundation
import Observation

/// Состояние экрана «Команда» — 1:1 поведение `useAgents`/`useCreateAgent`/
/// `useRenameAgent`/`useDeleteAgent` (`src/api/agents.ts`, `AgentsScreen.tsx`).
/// Свой `APIClient` — по тем же причинам, что у `ChatViewModel` (см. её
/// комментарий): в environment `Sources/App/` живут только `TaskStore`/
/// `ProjectStore`/`LabelStore`/`NotificationStore`/`SessionStore`, стора
/// агентов там нет.
@MainActor
@Observable
final class AgentsViewModel {
    private(set) var agents: [ApiUser] = []
    private(set) var isLoading = false
    var listErrorMessage: String?
    var deleteErrorMessage: String?

    /// Ключ только что заведённого агента — сервер отдаёт его РОВНО ОДИН
    /// раз в ответе создания, больше ни одним маршрутом. Живёт только в
    /// памяти экрана (SCREENS-2 §4). `agentID` нужен, чтобы в раскрытой
    /// карточке отличить «свой только что выпущенный ключ» от «чужого,
    /// для которого ключ сервер не возвращает» — в первом случае показываем
    /// реальное значение под глазиком, во втором — поле ввода «нет токена».
    private(set) var issuedToken: (agentID: String, name: String, token: String)?
    var createErrorMessage: String?
    var renameErrorMessage: String?
    var avatarErrorMessage: String?

    private(set) var isOwner = false

    /// Какой агент сейчас раскрыт в карточке — `nil`, если все свёрнуты.
    /// Один на весь экран: при тапе по другому агенту старый сворачивается.
    private(set) var expandedAgentID: String?

    /// Черновик API-токена по агенту — редактируемое поле «если нет токена,
    /// впишите свой». Сервер хранит только хеш и не возвращает исходный ключ;
    /// `PUT /api/agents/:id/api-token` принимает новое значение один раз.
    private(set) var tokenDrafts: [String: String] = [:]

    /// Какие токены сейчас видны (глазик `eye.slash` → `eye`). Состояние
    /// живёт в VM, а не в строке — переживает перерисовку списка.
    private(set) var revealedTokenIDs: Set<String> = []

    /// Кэш детальной карточки по агенту (LOCK-146). Грузится по тапу
    /// `toggleExpand`, переживает сворачивание — при следующем раскрытии
    /// того же агента детали уже есть, запрос не повторяется. `refresh()`
    /// перезапрашивает принудительно.
    private(set) var details: [String: AgentDetails] = [:]
    /// Какой агент сейчас грузится — нужен, чтобы UI показал индикатор.
    private(set) var detailsLoadingID: String?
    /// Ошибка последней загрузки деталей (сбрасывается на следующий toggle).
    var detailsErrorMessage: String?
    /// Каталоги MCP-серверов и скиллов — общие на всех агентов, грузятся
    /// один раз при первом открытии любой карточки.
    private(set) var mcpCatalog: [McpCatalogEntry] = []
    private(set) var skillCatalog: [SkillCatalogEntry] = []
    private(set) var catalogLoaded = false

    private let api = APIClient()
    private var pollTask: Task<Void, Never>?

    /// `SessionStore.currentUser` приходит из `@Environment`, недоступного
    /// внутри `init()` вью — экран зовёт это явно в `.task` до `start()`.
    func configure(currentUser: ApiUser?) {
        isOwner = currentUser?.role == .owner
    }

    /// Раз в 15с (веб: `refetchInterval: 15000`) — присутствие/лимиты живые.
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

    // MARK: - Раскрытие / токен

    /// Тап по строке — toggle. Тап по уже раскрытому закрывает; тап по другому
    /// открывает его (старый закрывается автоматически, потому что
    /// `expandedAgentID` один).
    func toggleExpand(_ agentID: String) {
        if expandedAgentID == agentID {
            expandedAgentID = nil
            // Очищаем черновик, чтобы при следующем раскрытии поле было пустым.
            tokenDrafts.removeValue(forKey: agentID)
            revealedTokenIDs.remove(agentID)
        } else {
            expandedAgentID = agentID
        }
    }

    func isExpanded(_ agentID: String) -> Bool {
        expandedAgentID == agentID
    }

    func updateTokenDraft(_ agentID: String, value: String) {
        if value.isEmpty {
            tokenDrafts.removeValue(forKey: agentID)
        } else {
            tokenDrafts[agentID] = value
        }
    }

    func tokenDraft(for agentID: String) -> String {
        tokenDrafts[agentID] ?? ""
    }

    func toggleTokenReveal(_ agentID: String) {
        if revealedTokenIDs.contains(agentID) {
            revealedTokenIDs.remove(agentID)
        } else {
            revealedTokenIDs.insert(agentID)
        }
    }

    func isTokenRevealed(_ agentID: String) -> Bool {
        revealedTokenIDs.contains(agentID)
    }

    /// Сохранить введённый токен через `PUT /api/agents/:id/api-token`. Сервер
    /// хранит хешем, наружу не отдаёт; на клиенте после успеха очищаем
    /// черновик и помечаем деталь «токен только что задан» (используем тот же
    /// `issuedToken`-канал, что и для нового агента — поведение на UI
    /// идентичное).
    func saveTokenDraft(_ agentID: String) async -> Bool {
        let trimmed = (tokenDrafts[agentID] ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return false }
        do {
            try await api.saveAgentApiToken(agentId: agentID, token: trimmed)
            // В раскрытой панели покажем этот токен под глазиком — то же
            // поведение, что у только что созданного агента.
            issuedToken = (
                agentID,
                details[agentID]?.name ?? "",
                trimmed
            )
            clearTokenDraft(agentID)
            // Сервер не вернёт сырой токен обратно, но мы его только что
            // отправили — и он в issuedToken. Детали перечитываем, чтобы
            // подтянуть свежий `apiTokenSetAt`.
            await loadDetails(agentId: agentID, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    func clearTokenDraft(_ agentID: String) {
        tokenDrafts.removeValue(forKey: agentID)
    }

    /// Перевыпустить ключ через `POST /api/agents/:id/rotate-token`. Ответ
    /// содержит сырое значение — оно же попадает в `issuedToken`, чтобы
    /// раскрытая панель показала его под глазиком. После показа владелец
    /// копирует ключ и переустанавливает агента на своей стороне; на UI
    /// ключ хранится до сворачивания.
    func rotateAgentToken(_ agentID: String) async -> Bool {
        do {
            let response = try await api.rotateAgentApiToken(agentId: agentID)
            issuedToken = (response.agentId, response.name, response.apiToken)
            revealedTokenIDs.insert(agentID) // сразу показываем
            await loadDetails(agentId: agentID, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    // MARK: - Детали агента (LOCK-146)

    /// Загрузить детали агента. Пропускает сеть, если детали уже в кэше
    /// (toggle expand → toggle expand на том же агенте). При `force == true`
    /// перечитывает принудительно — после `saveTokenDraft`/`rotateAgentToken`/
    /// `updateAgentModel` и т. п.
    func loadDetails(agentId: String, force: Bool = false) async {
        if !force, details[agentId] != nil { return }
        detailsLoadingID = agentId
        detailsErrorMessage = nil
        defer { detailsLoadingID = nil }
        do {
            let d = try await api.agentDetails(id: agentId)
            details[agentId] = d
            // Каталоги — общие, тянем за первый раз попутно.
            if !catalogLoaded {
                async let mcp = api.mcpServersCatalog()
                async let skills = api.skillsCatalog()
                mcpCatalog = (try? await mcp) ?? []
                skillCatalog = (try? await skills) ?? []
                catalogLoaded = true
            }
        } catch {
            detailsErrorMessage = Self.message(for: error)
        }
    }

    /// Сбросить кэш деталей — после `deleteAgent` или принудительного
    /// обновления списка.
    func evictDetails(agentId: String) {
        details.removeValue(forKey: agentId)
    }

    func details(for agentId: String) -> AgentDetails? {
        details[agentId]
    }

    // MARK: - Мутации деталей (все owner-only, сервер вернёт 403 не-владельцу)

    /// Задать модель агента. `nil` — сбросить к дефолту.
    @discardableResult
    func updateModel(agentId: String, model: String?) async -> Bool {
        do {
            _ = try await api.updateAgentModel(agentId: agentId, model: model)
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Переключить агента между внешним runtime и прямым LLM API.
    @discardableResult
    func updateConnection(
        agentId: String,
        mode: AgentExecutionMode,
        provider: String?,
        model: String?,
        baseURL: String?,
        credentialRef: String?
    ) async -> Bool {
        do {
            _ = try await api.updateAgentConnection(
                agentId: agentId,
                mode: mode,
                provider: provider,
                model: model,
                baseURL: baseURL,
                credentialRef: credentialRef
            )
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Сохранить индивидуальный системный промпт агента.
    @discardableResult
    func updatePrompt(agentId: String, prompt: String?) async -> Bool {
        do {
            _ = try await api.updateAgentPrompt(agentId: agentId, prompt: prompt)
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Задать per-action права.
    @discardableResult
    func updatePermissions(agentId: String, permissions: AgentPermissions) async -> Bool {
        do {
            _ = try await api.updateAgentPermissions(
                agentId: agentId, permissions: permissions
            )
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Подключить MCP-сервер из каталога.
    @discardableResult
    func connectMcp(agentId: String, serverId: String) async -> Bool {
        do {
            _ = try await api.connectMcpServer(
                agentId: agentId, serverId: serverId, enabled: true
            )
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Отключить MCP-сервер.
    @discardableResult
    func disconnectMcp(agentId: String, serverId: String) async -> Bool {
        do {
            _ = try await api.disconnectMcpServer(
                agentId: agentId, serverId: serverId
            )
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Установить скилл из каталога.
    @discardableResult
    func installSkill(agentId: String, skillId: String) async -> Bool {
        do {
            _ = try await api.installSkill(
                agentId: agentId, skillId: skillId
            )
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// Удалить скилл.
    @discardableResult
    func uninstallSkill(agentId: String, skillId: String) async -> Bool {
        do {
            _ = try await api.uninstallSkill(
                agentId: agentId, skillId: skillId
            )
            await loadDetails(agentId: agentId, force: true)
            return true
        } catch {
            detailsErrorMessage = Self.message(for: error)
            return false
        }
    }

    func load() async {
        if agents.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            agents = try await api.agents()
            listErrorMessage = nil
        } catch {
            listErrorMessage = Self.message(for: error)
        }
    }

    func createAgent(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        createErrorMessage = nil
        do {
            let response = try await api.inviteAgentFixed(name: trimmed)
            issuedToken = (response.agent.id, response.agent.name, response.apiToken)
            await load()
        } catch {
            createErrorMessage = Self.message(for: error)
        }
    }

    func dismissIssuedToken() {
        issuedToken = nil
    }

    /// Реальный токен, который сервер отдал при создании и который ещё живёт
    /// в памяти экрана. После перезапуска экрана `issuedToken == nil` — для
    /// всех агентов это значит «сервер токен не отдаёт, нужно ввести свой».
    func realToken(for agentID: String) -> String? {
        guard let issued = issuedToken, issued.agentID == agentID else { return nil }
        return issued.token
    }

    func renameAgent(id: String, name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true } // как в вебе — пустое/неизменное просто закрывает форму
        renameErrorMessage = nil
        do {
            _ = try await api.renameAgentFixed(id: id, name: trimmed)
            await load()
            return true
        } catch {
            renameErrorMessage = Self.message(for: error)
            return false
        }
    }

    func deleteAgent(_ agent: ApiUser) async {
        deleteErrorMessage = nil
        do {
            try await api.deleteAgent(id: agent.id)
            await load()
        } catch {
            deleteErrorMessage = Self.message(for: error)
        }
    }

    func uploadAvatar(agentId: String, data: Data, mime: String) async {
        avatarErrorMessage = nil
        do {
            _ = try await api.uploadAgentAvatar(id: agentId, data: data, mime: mime)
            await load()
        } catch {
            avatarErrorMessage = Self.message(for: error)
        }
    }

    func removeAvatar(agentId: String) async {
        avatarErrorMessage = nil
        do {
            try await api.deleteAgentAvatar(id: agentId)
            await load()
        } catch {
            avatarErrorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
