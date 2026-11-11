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
