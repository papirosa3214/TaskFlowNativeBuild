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
    /// Общая настройка «Сначала проверка Reviewer» для новых карточек.
    /// У серверов старее поля нет — тогда считаем включённой, как раньше.
    public let reviewerFirstDefault: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case reviewerFirstDefault = "reviewer_first_default"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(TaskIntakeMode.self, forKey: .mode)
        reviewerFirstDefault = try c.decodeIfPresent(Bool.self, forKey: .reviewerFirstDefault) ?? true
    }
}

/// Ответ `GET/POST /api/agent-service`.
///
/// `enabled` — включён ли systemd-юнит, `active` — работает ли он прямо
/// сейчас. Владельцу показываем второе: включённая, но упавшая система
/// карточку не возьмёт, и тумблер обязан показывать факт, а не намерение.
public struct SystemRunState: Decodable, Sendable {
    public let active: Bool
    public let enabled: Bool
    /// Ближайший обход доски. Система проверяет назначенное раз в несколько
    /// минут, и владельцу важно видеть, сколько ждать: без этого работающая
    /// система выглядит одинаково и за десять секунд до обхода, и сразу
    /// после него. `nil` — система остановлена либо сервер старой версии.
    public let nextScanAt: Date?
    /// Период обхода в секундах — приходит с сервера, чтобы экран не зашивал
    /// своё число и не разошёлся с настоящим расписанием.
    public let scanIntervalSec: Int?

    enum CodingKeys: String, CodingKey {
        case active
        case enabled
        case nextScanAt = "next_scan_at"
        case scanIntervalSec = "scan_interval_sec"
    }

    // Поля добавлены 16.09.2026 и отсутствуют у серверов старее — поэтому
    // декодируются мягко. Уронить весь экран состояния из-за отсутствующего
    // таймера нельзя: тумблер системы важнее подписи под ним.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decode(Bool.self, forKey: .active)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        scanIntervalSec = try c.decodeIfPresent(Int.self, forKey: .scanIntervalSec)
        if let raw = try c.decodeIfPresent(String.self, forKey: .nextScanAt) {
            nextScanAt = ISO8601DateFormatter.systemControl.date(from: raw)
        } else {
            nextScanAt = nil
        }
    }
}

private extension ISO8601DateFormatter {
    /// Сервер отдаёт время через `toISOString()` — с миллисекундами, поэтому
    /// разбор без `withFractionalSeconds` молча возвращал бы nil.
    static let systemControl: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private struct SystemToggleBody: Encodable { let on: Bool }
private struct SystemToggleAck: Decodable { let ok: Bool }
private struct TaskIntakeModeBody: Encodable { let mode: TaskIntakeMode }
private struct ReviewerFirstBody: Encodable { let reviewer_first_default: Bool }

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

    /// Общая настройка «Сначала проверка Reviewer» для новых карточек —
    /// тот же маршрут настроек, отдельным полем.
    func updateReviewerFirstDefault(_ on: Bool) async throws -> TaskIntakeSettings {
        try await request(.patch, "/task-intake/settings", body: ReviewerFirstBody(reviewer_first_default: on))
    }
}
