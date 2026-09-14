import Foundation

// Две серверные ручки владельца, которыми управляет карточка на «Обзоре»:
// работает ли система и что она делает с надиктовкой.
//
// Лежит в `Core/Networking` рядом с остальными расширениями `APIClient`
// (`APIClient+AgentDetails.swift`, `APIClient+Reviews.swift`), а не во
// вью-модели экрана: слой транспорта в проекте отделён от экранного
// состояния, и второй разбор тех же ответов рядом с UI разошёлся бы с
// первым при первой же правке контракта.

/// Как сервер поступает с надиктовкой владельца в окно постановки.
///
/// `manual` — разбор останавливается на черновике: владелец открывает
/// карточку, правит и сам поднимает флаг готовности.
/// `automatic` — сервер поднимает флаг и отдаёт работу исполнителю сам,
/// черновик владельцу не показывается и подтверждения не ждёт.
///
/// Значение живёт НА СЕРВЕРЕ (`users.task_intake_mode`), а не в
/// `UserDefaults`: им пользуется конвейер разбора, и снимок с него
/// снимается в момент приёма сообщения. Локальная копия на телефоне
/// разошлась бы и с вебом, и с тем, что реально сделает сервер.
public enum TaskIntakeMode: String, Codable, Sendable {
    case manual
    case automatic
}

public struct TaskIntakeSettings: Codable, Sendable {
    public let mode: TaskIntakeMode
}

/// Ответ `GET/POST /api/agent-service`.
///
/// `enabled` — включён ли systemd-юнит, `active` — работает ли он прямо
/// сейчас. Владельцу показываем второе: включённая, но упавшая система
/// карточку не возьмёт, и тумблер обязан показывать факт, а не намерение.
public struct SystemRunState: Decodable, Sendable {
    public let active: Bool
    public let enabled: Bool
}

private struct SystemToggleBody: Encodable { let on: Bool }
private struct SystemToggleAck: Decodable { let ok: Bool }
private struct TaskIntakeModeBody: Encodable { let mode: TaskIntakeMode }

public extension APIClient {
    func fetchSystemRunState() async throws -> SystemRunState {
        try await request(.get, "/agent-service")
    }

    /// `POST /api/agent-service` отдаёт только `{ ok }`, а systemd применяет
    /// изменение не мгновенно — поэтому состояние не выводится из ответа, а
    /// перечитывается. Эхо запроса показало бы «работает» раньше, чем
    /// система реально встала.
    func setSystemRunning(_ on: Bool) async throws -> SystemRunState {
        let ack: SystemToggleAck = try await request(.post, "/agent-service", body: SystemToggleBody(on: on))
        guard ack.ok else { throw APIError.transport(URLError(.badServerResponse)) }
        return try await fetchSystemRunState()
    }

    func fetchTaskIntakeSettings() async throws -> TaskIntakeSettings {
        try await request(.get, "/task-intake/settings")
    }

    /// Нераспознанный режим сервер отклоняет с 400 и базу не трогает,
    /// поэтому источник правды — его ответ, а не наше намерение.
    func updateTaskIntakeMode(_ mode: TaskIntakeMode) async throws -> TaskIntakeSettings {
        try await request(.patch, "/task-intake/settings", body: TaskIntakeModeBody(mode: mode))
    }
}
