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
        public let subtaskId: String?
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
        public var title: String? = nil
        public var done: Bool? = nil
        public var skipped: Bool? = nil
        public var assigneeName: String? = nil
        public var waitingFor: [String]? = nil
        public var id: String { subtaskId ?? "task:\(taskId)" }
        public var displayTitle: String { title ?? planNodeKey ?? "Задача" }
        public var displayStatus: String { skipped == true ? "Шаг пропущен" : done == true ? "Шаг завершён" : causeEnum.title }


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
            case links, title, done, skipped
            case assigneeName = "assignee_name"
            case waitingFor = "waiting_for"
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
        public let href: String
        public let rel: String
        public let note: String?
        public var kind: String { rel }
        public var ref: String { href }
    }

    /// Сервер возвращает {task_id, resolutions}. Поддерживаем также старые
    /// конверт items и массив в корне, без повторного HTTP-запроса.
    struct TaskResolutions: Decodable, Sendable, Equatable {
        public let items: [CoordinationResolution]
        enum CodingKeys: String, CodingKey { case items, resolutions }
        public init(from decoder: Decoder) throws {
            if let array = try? decoder.singleValueContainer().decode([CoordinationResolution].self) {
                items = array
            } else {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                items = try c.contains(.resolutions)
                    ? c.decode([CoordinationResolution].self, forKey: .resolutions)
                    : c.decode([CoordinationResolution].self, forKey: .items)
            }
        }
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
        let response: TaskResolutions = try await request(.get, "/coordination/tasks/\(taskId)/resolve")
        return response.items
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

public extension APIClient.CoordinationResolution {
    /// Решения с выбором параметров открывают уже существующее управление.
    var controlLabel: String? {
        guard done != true, skipped != true, causeEnum != .unknown else { return nil }
        switch actionEnum {
        case .replaceAttempt:
            return canRestartStep ? "Перезапустить шаг" : "Открыть управление задачей"
        case .switchProvider, .fixConfig: return "Открыть настройки моделей"
        case .liftDependency: return "Открыть зависимости задачи"
        case .askOwner: return "Ответить в задаче"
        case .switchRole: return "Выбрать исполнителя в задаче"
        case .acceptReview: return "Открыть приёмку задачи"
        case .start, .runFinalReview, .pickUpAfterReview, .retryWithDelay: return "Открыть управление задачей"
        case .waitPredecessor, .noAction, .none: return nil
        }
    }
    var canRestartStep: Bool {
        done != true && skipped != true && causeEnum != .unknown && actionEnum == .replaceAttempt
            && subtaskId != nil && planNodeKey != nil && role != nil
    }
}

public extension APIClient {
    func restartCoordinationStep(_ selected: CoordinationResolution, reason: String) async throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1000 else {
            throw NSError(domain: "Coordination", code: 400, userInfo: [NSLocalizedDescriptionKey: "Укажите причину перезапуска (до 1000 символов)"])
        }
        // Подтверждение могло открыться до обновления шага. Перечитываем его.
        let current = try await fetchTaskResolutions(taskId: selected.taskId)
        guard let latest = current.first(where: { $0.id == selected.id }),
              latest.contractVersion == "2.0.0", latest.canRestartStep,
              latest.role == selected.role,
              let id = latest.subtaskId, let role = latest.role else {
            throw NSError(domain: "Coordination", code: 409, userInfo: [NSLocalizedDescriptionKey: "Состояние шага изменилось. Обновите координацию."])
        }
        struct Body: Encodable { let role: String; let reason: String }
        struct Result: Decodable { let ok: Bool }
        let result: Result = try await request(.post, "/subtasks/\(id)/restart", body: Body(role: role, reason: trimmed))
        guard result.ok else {
            throw NSError(domain: "Coordination", code: 409, userInfo: [NSLocalizedDescriptionKey: "Сервер не подтвердил перезапуск шага"])
        }
    }
}
