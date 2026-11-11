import Foundation

/// LOCK-146, серверная половина. Детальная карточка агента: модель,
/// права, MCP-серверы (Composio/Smithery), скиллы. Каталоги MCP/скиллов —
/// публичные для авторизованных. Мутации (подключение MCP, установка
/// скилла, смена модели/прав/токена) — только владелец; сервер всё
/// равно валидирует и вернёт 403 не-владельцу, на клиенте дополнительной
/// проверки нет.
///
/// Контракты — см. `server/src/routes/agent-details.ts` (LOCK-146).
public extension APIClient {

    // MARK: - Мутации (owner)

    /// Подключить MCP-сервер агенту. `config` — пользовательская правка
    /// поверх `defaultConfig` каталога (токены, scope, фильтры). `enabled`
    /// по умолчанию true; false — записать в БД, но не использовать.
    @discardableResult
    func connectMcpServer(
        agentId: String,
        serverId: String,
        config: [String: JSONValue]? = nil,
        enabled: Bool = true
    ) async throws -> APIOkResponse {
        var body: [String: JSONValue] = [
            "serverId": .string(serverId),
            "enabled": .bool(enabled),
        ]
        if let config { body["config"] = .object(config) }
        return try await request(
            .post, "/agents/\(agentId)/mcp-servers",
            body: body
        )
    }

    /// Отключить MCP-сервер у агента (удалить запись подключения).
    @discardableResult
    func disconnectMcpServer(
        agentId: String,
        serverId: String
    ) async throws -> APIOkResponse {
        try await request(
            .delete,
            "/agents/\(agentId)/mcp-servers/\(Self.agentDetailsPathSegment(serverId))"
        )
    }

    /// Установить скилл агенту.
    @discardableResult
    func installSkill(
        agentId: String,
        skillId: String,
        config: [String: JSONValue]? = nil
    ) async throws -> APIOkResponse {
        var body: [String: JSONValue] = ["skillId": .string(skillId)]
        if let config { body["config"] = .object(config) }
        return try await request(.post, "/agents/\(agentId)/skills", body: body)
    }

    /// Удалить скилл у агента.
    @discardableResult
    func uninstallSkill(
        agentId: String,
        skillId: String
    ) async throws -> APIOkResponse {
        try await request(
            .delete,
            "/agents/\(agentId)/skills/\(Self.agentDetailsPathSegment(skillId))"
        )
    }

    /// Задать модель агента. `nil`/пустая строка — сброс к дефолту (NULL).
    @discardableResult
    func updateAgentModel(
        agentId: String,
        model: String?
    ) async throws -> APIOkResponse {
        try await request(
            .put, "/agents/\(agentId)/model",
            body: ["model": model.map(JSONValue.string) ?? .null]
        )
    }

    /// Сохранить индивидуальный системный промпт. `nil`/пустая строка —
    /// использовать внешний или ролевой промпт по умолчанию.
    @discardableResult
    func updateAgentPrompt(
        agentId: String,
        prompt: String?
    ) async throws -> APIOkResponse {
        try await request(
            .put, "/agents/\(agentId)/prompt",
            body: ["prompt": prompt.map(JSONValue.string) ?? .null]
        )
    }

    /// Сохранить свой ключ доступа (когда сервер не отдал — например, для
    /// агента, заведённого в другой сессии). Хранится хешем, наружу больше
    /// не возвращается.
    @discardableResult
    func saveAgentApiToken(
        agentId: String,
        token: String
    ) async throws -> APIOkResponse {
        try await request(
            .put, "/agents/\(agentId)/api-token",
            body: ["token": token]
        )
    }

    /// Перевыпустить ключ. Ответ содержит сырое значение **ровно один
    /// раз** — на UI показать владельцу и сразу очистить из памяти после
    /// копирования, чтобы случайно не утекло в логи/скриншоты.
    func rotateAgentApiToken(agentId: String) async throws -> RotatedAgentToken {
        try await request(.post, "/agents/\(agentId)/rotate-token")
    }

    /// Каталожные id содержат `/` (`composio/github`), поэтому для DELETE
    /// их нужно кодировать именно как один сегмент пути. `.urlPathAllowed`
    /// здесь не подходит: она намеренно оставляет slash незакодированным.
    private static func agentDetailsPathSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Ответ `POST /api/agents/:id/rotate-token` — сырое значение токена
/// показывается один раз.
public struct RotatedAgentToken: Codable, Sendable, Hashable {
    public let agentId: String
    public let name: String
    public let apiToken: String
}
