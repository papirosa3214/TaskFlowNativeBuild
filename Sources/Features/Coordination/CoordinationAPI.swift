import Foundation

/// Маршруты `GET /api/coordination/*` — резолвер причин движения/ожидания.
/// Контракт снят с `server/src/runtime/coordinationResolver.ts` и
/// `server/src/routes/coordination.ts` (коммит eb36437b, карточка
/// `3161afe9-…`). Документация контракта — `docs/server/coordination-resolver.md`;
/// UX-документ iOS — `docs/ios/coordination-resolver-view.md`.
///
/// Сценарий: iOS открывает карточку, раз в 30 с (или чаще при активной
/// работе) запрашивает `tasks/:id/resolve`. Сервер отдаёт массив
/// `Resolution` — по одному на каждый узел плана и личный шаг. Клиент
/// только рисует. Действия по-прежнему делаются через существующие
/// маршруты (`POST /api/subtasks/:id/restart`, owner-controls и др.).
///
/// Имена полей дословно совпадают с JSON-сервером (snake_case через
/// `CodingKeys`), чтобы тот же документ контракта оставался каноном и
/// для Web, и для iOS.
public extension APIClient {

    /// Один узел карточки: причина движения/ожидания, действие,
    /// исполнитель, доказательства. Сервер V2, `contract_version=2.0.0`.
    struct CoordinationResolution: Decodable, Sendable, Equatable {
        public let contractVersion: String
        public let generatedAt: String
        public let subtaskId: String
        public let taskId: String
        public let planNodeKey: String?
        public let role: String?
        public let cause: String
        public let action: String
        public let assignee: CoordinationAssignee
        public let deadlineHint: String?
        public let checkedAfter: String?
        public let evidence: [CoordinationEvidence]
        public let metrics: CoordinationMetrics
        public let notes: String?
        public let links: [CoordinationLink]

        enum CodingKeys: String, CodingKey {
            case contractVersion = "contract_version"
            case generatedAt = "generated_at"
            case subtaskId = "subtask_id"
            case taskId = "task_id"
            case planNodeKey = "plan_node_key"
            case role
            case cause
            case action
            case assignee
            case deadlineHint = "deadline_hint"
            case checkedAfter = "checked_after"
            case evidence
            case metrics
            case notes
            case links
        }
    }

    /// Кто отвечает за узел сейчас. `kind=person` означает владельца
    /// карточки (по дефолту V2 координатор не пишется — решение владельца
    /// «V2 пишет владельца карточки»).
    struct CoordinationAssignee: Decodable, Sendable, Equatable {
        public let kind: String  // "role" | "person"
        public let key: String
    }

    /// Доказательство — пара «метка + ссылка». Сервер гарантирует, что
    /// `ref` указывает на конкретную запись в БД (таблица.основание).
    struct CoordinationEvidence: Decodable, Sendable, Equatable {
        public let kind: String
        public let ref: String
    }

    /// Минимальный снимок состояния: возраст, число попыток в окне,
    /// свежесть heartbeat активной попытки.
    struct CoordinationMetrics: Decodable, Sendable, Equatable {
        public let ageSeconds: Int
        public let attemptsInWindow: Int
        public let heartbeatAge: Int

        enum CodingKeys: String, CodingKey {
            case ageSeconds = "age_seconds"
            case attemptsInWindow = "attempts_in_window"
            case heartbeatAge = "heartbeat_age"
        }
    }

    /// Ссылка на связанные действия и узлы графа.
    struct CoordinationLink: Decodable, Sendable, Equatable {
        public let kind: String
        public let ref: String
    }

    /// Конверт `GET /api/coordination/tasks/:id/resolve` — массив
    /// `Resolution` по всем подзадачам карточки (узлы плана + личные).
    /// Имя массива — `items`; сервер V2 в ответе кладёт массив в корень,
    /// но оборачиваем в конверт, чтобы клиенту было удобно диффовать.
    struct TaskResolutions: Decodable, Sendable, Equatable {
        public let items: [CoordinationResolution]
    }

    /// Конверт `GET /api/coordination/_metrics?window=hour|day` — счётчики
    /// по причинам и действиям + список «непонятных» узлов.
    struct CoordinationMetricsResponse: Decodable, Sendable, Equatable {
        public let window: String
        public let since: String
        public let until: String
        public let counts: [String: Int]
        public let actions: [String: Int]
        public let topUnknownSubtasks: [TopUnknown]

        public struct TopUnknown: Decodable, Sendable, Equatable {
            public let subtaskId: String
            public let lastSeenAt: String

            enum CodingKeys: String, CodingKey {
                case subtaskId = "subtask_id"
                case lastSeenAt = "last_seen_at"
            }
        }
    }

    /// `GET /api/coordination/tasks/:id/resolve` — список `Resolution` по
    /// подзадачам карточки.
    func fetchTaskResolutions(taskId: String) async throws -> [CoordinationResolution] {
        // Сервер отдаёт массив в корне: ради совместимости с уже принятым
        // клиентом декодируем и в массив, и в конверт — берём первый, что
        // не упал.
        if let envelope: TaskResolutions = try? await request(
            .get, "/coordination/tasks/\(taskId)/resolve"
        ) {
            return envelope.items
        }
        return try await request(
            .get, "/coordination/tasks/\(taskId)/resolve"
        )
    }

    /// `GET /api/coordination/subtasks/:id/resolve` — один `Resolution`
    /// по конкретному узлу (используется при тапе на узел графа для
    /// детального sheet).
    func fetchSubtaskResolution(subtaskId: String) async throws -> CoordinationResolution {
        try await request(.get, "/coordination/subtasks/\(subtaskId)/resolve")
    }

    /// `GET /api/coordination/attempts/:id/resolve` — что случилось с
    /// конкретной попыткой. Нужен для ленты «история шага» в Details.
    func fetchAttemptResolution(attemptId: String) async throws -> CoordinationResolution {
        try await request(.get, "/coordination/attempts/\(attemptId)/resolve")
    }

    /// `GET /api/coordination/_metrics?window=hour|day` — счётчики.
    func fetchCoordinationMetrics(window: String = "hour") async throws -> CoordinationMetricsResponse {
        try await request(
            .get,
            "/coordination/_metrics",
            query: [URLQueryItem(name: "window", value: window)]
        )
    }
}