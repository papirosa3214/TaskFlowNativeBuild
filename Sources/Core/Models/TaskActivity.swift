import Foundation

/// Живая строка «чем агент занят прямо сейчас» — `GET /api/tasks/:id/activity`.
///
/// Сервер собирает её тремя слоями (`server/src/routes/activity.ts`): название
/// текущего шага, типизация действия по инструменту и пути, и поверх —
/// пересказ локальной моделью. Клиент печатает `text` как есть и ничего не
/// доформулировывает: сырые пути и команды владелец видеть не хочет,
/// готовую формулировку по каждому действию сервер уже кладёт в `text`.
///
/// Буфер в памяти живёт 30 минут и гаснет, когда задача уходит в архив.
/// История же работы роли лежит в журнале `role_tool_audit` — он живёт
/// вместе с задачей, и по нему сервер считает статистику (`stats`): сколько
/// операций, сколько успешных, сколько ошибок и по каким. Владелец
/// 02.11.2026: «у меня нет информации, почему оно падает» — статистика и
/// есть этот ответ.
public struct ApiTaskActivity: Codable, Sendable, Hashable {
    /// Одна фраза о происходящем. `nil` — агент задачу не держит.
    public let text: String?
    public let actions: [ApiTaskActivityAction]
    /// Сколько всего действий было с начала работы (сервер считает без лимита). `nil` — старый сервер.
    public var total: Int? = nil

    public var bySubtask: [String: ApiTaskActivity]? = nil

    /// Статистика действий роли по журналу. `nil` — старый сервер.
    public var stats: ApiTaskActivityStats? = nil

    enum CodingKeys: String, CodingKey {
        case text, actions, total, stats
        case bySubtask = "by_subtask"
    }

    /// Старый общий счётчик не выдаём за активность конкретного исполнителя.
    public func forSubtask(_ id: String?) -> ApiTaskActivity {
        guard let id else { return .idle }
        return bySubtask?[id] ?? .idle
    }

    public static let idle = ApiTaskActivity(text: nil, actions: [])

    public var isActive: Bool { text?.isEmpty == false || !actions.isEmpty }
}

/// Статистика действий роли по журналу `role_tool_audit` (сервер
/// `roleActionStats`): сколько операций, сколько успешных, сколько ошибок и
/// по каким операциям.
public struct ApiTaskActivityStats: Codable, Sendable, Hashable {
    /// Одна операция: сколько раз звали и сколько раз с ошибкой.
    public struct Operation: Codable, Sendable, Hashable, Identifiable {
        public let operation: String
        public let total: Int
        public let failed: Int
        public var id: String { operation }
    }

    /// Одна ошибка: операция, текст и когда.
    public struct Failure: Codable, Sendable, Hashable, Identifiable {
        public let operation: String
        public let message: String
        public let at: String
        public var id: String { "\(operation)-\(at)-\(message.prefix(12))" }
    }

    public let total: Int
    public let ok: Int
    public let failed: Int
    public let byOperation: [Operation]
    public let errors: [Failure]

    enum CodingKeys: String, CodingKey {
        case total, ok, failed, errors
        case byOperation = "by_operation"
    }

    /// Операции, по которым были ошибки, — «в основном ошибки по каким
    /// командам» (владелец 02.11.2026).
    public var failedOperations: [Operation] {
        byOperation.filter { $0.failed > 0 }.sorted { $0.failed > $1.failed }
    }
}

public struct ApiTaskActivityAction: Codable, Sendable, Hashable, Identifiable {
    public let kind: String
    public let target: String
    public let detail: String?
    public let actor: String
    /// Unix-миллисекунды от сервера.
    public let at: Double
    /// Готовая формулировка от сервера — печатать как есть.
    public let text: String?

    public var id: String { "\(actor)-\(at)-\(target)" }

    public var date: Date { Date(timeIntervalSince1970: at / 1000) }
}
