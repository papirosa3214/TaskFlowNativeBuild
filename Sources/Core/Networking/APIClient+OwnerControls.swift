import Foundation

// Кнопки владельца: возобновление зависших шагов и перезапуск сервера (MAK-76).
// Только владелец: остальным сервер отвечает 403, поэтому показываем эти
// действия только владельцу, а права проверяет сервер.

/// Состояние для экрана: сколько запусков идёт и сколько шагов зависло.
public struct OwnerRuntimeStatus: Decodable, Sendable {
    public let activeRuns: Int
    public let stuckCount: Int

    enum CodingKeys: String, CodingKey {
        case activeRuns = "active_runs"
        case stuck
    }

    /// Нужно только количество зависших; сами шаги экрану не нужны.
    private struct StuckStep: Decodable {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeRuns = try c.decode(Int.self, forKey: .activeRuns)
        stuckCount = try c.decodeIfPresent([StuckStep].self, forKey: .stuck)?.count ?? 0
    }
}

/// Итог «Возобновить зависшие шаги».
public struct OwnerResumeResult: Decodable, Sendable {
    public let found: Int
    public let resumed: Int
    public let blocked: Int
    public let freed: Int
}

/// Ответ на «Перезапустить сервер»: команда принята, перезапуск идёт.
public struct OwnerRestartAck: Decodable, Sendable {
    public let accepted: Bool
    public let activeRuns: Int

    enum CodingKeys: String, CodingKey {
        case accepted
        case activeRuns = "active_runs"
    }
}

private struct OwnerEmptyBody: Encodable {}
private struct OwnerRestartBody: Encodable { let confirm: Bool }

public extension APIClient {
    func fetchOwnerRuntimeStatus() async throws -> OwnerRuntimeStatus {
        try await request(.get, "/owner/runtime-status")
    }

    /// Возобновляет шаги «в работе» без живого запуска; сервер при этом не
    /// перезапускается.
    func resumeStuckSteps() async throws -> OwnerResumeResult {
        try await request(.post, "/owner/resume-stuck", body: OwnerEmptyBody())
    }

    /// Перезапуск оборвёт идущие запуски, поэтому сервер требует
    /// `confirm: true`. Подтверждение берётся у владельца до вызова.
    func restartServer() async throws -> OwnerRestartAck {
        try await request(.post, "/owner/restart-server", body: OwnerRestartBody(confirm: true))
    }
}
