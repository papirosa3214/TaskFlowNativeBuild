import Foundation

struct TaskFlowWebhook: Decodable, Identifiable, Sendable {
    struct Wake: Codable, Sendable {
        let codexThreadID: String?
        let lastWakeAt: String?
        let lastWakeError: String?
        enum CodingKeys: String, CodingKey {
            case codexThreadID = "codex_thread_id"
            case lastWakeAt = "last_wake_at", lastWakeError = "last_wake_error"
        }
    }
    let id: String
    let name: String
    let url: String
    let enabled: Bool
    let eventKinds: [String]
    let projectID: String?
    let lastDeliveryAt: String?
    let lastError: String?
    let wakeConfirmedAt: String?
    let wake: Wake?
    /// Счётчики и код последнего ответа приёмника — для сводной строки
    /// «работают / не работают» в секции «Сервер» настроек (12.10.2026).
    /// Раньше они не декодировались: экран «Вебхуки» их не показывал, и
    /// сводки не было. Опциональные — старый сервер без этих полей не ломает
    /// разбор ответа.
    let deliveryCount: Int?
    let wakeCount: Int?
    let lastDeliveryStatus: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, url, enabled, wake
        case eventKinds = "event_kinds", projectID = "project_id"
        case lastDeliveryAt = "last_delivery_at", lastError = "last_error"
        case wakeConfirmedAt = "wake_confirmed_at"
        case deliveryCount = "delivery_count", wakeCount = "wake_count"
        case lastDeliveryStatus = "last_delivery_status"
    }
}

struct WebhookSettingsBody: Encodable {
    let name: String
    let url: String
    let secret: String?
    let enabled: Bool
    let eventKinds: [String]
    let projectID: String?
    let wake: TaskFlowWebhook.Wake?

    enum CodingKeys: String, CodingKey {
        case name, url, secret, enabled, wake
        case eventKinds = "event_kinds", projectID = "project_id"
    }
}

struct WebhookTestResult: Decodable, Sendable {
    let delivered: Bool
    let wakeConfirmed: Bool
    let error: String?
    enum CodingKeys: String, CodingKey {
        case delivered, error
        case wakeConfirmed = "wake_confirmed"
    }
    var message: String {
        if !delivered { return error ?? "Приёмник не подтвердил доставку." }
        if wakeConfirmed { return "Доставлено. Запуск оркестратора подтверждён." }
        return "Доставлено. Запуск оркестратора ещё не подтверждён."
    }
}

extension APIClient {
    func webhooks() async throws -> [TaskFlowWebhook] {
        struct Response: Decodable { let webhooks: [TaskFlowWebhook] }
        let response: Response = try await request(.get, "/integrations/webhooks")
        return response.webhooks
    }
    func saveWebhook(id: String?, body: WebhookSettingsBody) async throws {
        struct Response: Decodable { let webhook: TaskFlowWebhook }
        let _: Response = try await request(id == nil ? .post : .patch,
            "/integrations/webhooks" + (id.map { "/\($0)" } ?? ""), body: body)
    }
    func deleteWebhook(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/integrations/webhooks/\(id)")
    }
    func testWebhook(id: String) async throws -> WebhookTestResult {
        try await request(.post, "/integrations/webhooks/\(id)/test")
    }
}
