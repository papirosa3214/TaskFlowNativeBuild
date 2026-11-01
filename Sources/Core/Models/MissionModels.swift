import Foundation

/// Контракт ассерций миссии — сервер TaskFlow (.110, миграции 189–191).
///
/// «Готово» здесь определено **до** работы: список проверяемых утверждений.
/// Работа (узел плана) закрывает ассерции полем `fulfills`, проверяющий сдаёт
/// результат по каждой, а серверный гейт превращает непройденную ассерцию в
/// доработку. До появления контракта «готово» означало «критик посмотрел и
/// одобрил» — критерии подгонялись под получившееся.
public struct MissionAssertion: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let assertionId: String
    public let area: String?
    public let title: String
    public let behavior: String
    public let tool: String?
    public let status: String
    /// Ключ шага плана, который закрыл ассерцию.
    public let claimedBySlot: String?

    enum CodingKeys: String, CodingKey {
        case id, area, title, behavior, tool, status
        case assertionId = "assertion_id"
        case claimedBySlot = "claimed_by_slot"
    }
}

/// Статус ассерции. Неизвестное значение сервера считаем «не проверена» —
/// падать на новом статусе нельзя, экран должен остаться читаемым.
public enum MissionAssertionStatus: Sendable, Hashable {
    case pending
    case passed
    case failed
    case blocked

    public init(_ raw: String) {
        switch raw {
        case "passed": self = .passed
        case "failed": self = .failed
        case "blocked": self = .blocked
        default: self = .pending
        }
    }

    public var title: String {
        switch self {
        case .pending: return "Не проверена"
        case .passed: return "Пройдена"
        case .failed: return "Не пройдена"
        case .blocked: return "Не проверяется вживую"
        }
    }
}

public extension MissionAssertion {
    var statusEnum: MissionAssertionStatus { MissionAssertionStatus(status) }
}

/// Итог по контракту: закрыта ли миссия и что ещё не выполнено.
public struct MissionOutcome: Decodable, Hashable, Sendable {
    public let hasContract: Bool
    public let total: Int
    public let passed: Int
    public let failed: Int
    public let blocked: Int
    public let pending: Int
    public let closed: Bool
    /// id ассерций, которые ещё не `passed`.
    public let outstanding: [String]

    enum CodingKeys: String, CodingKey {
        case hasContract = "has_contract"
        case total, passed, failed, blocked, pending, closed, outstanding
    }
}

/// Событие журнала миссии: кто что проверял, что упало, какая доработка
/// открылась. Журнал append-only — на экране он и есть история прохождения
/// контракта.
public struct MissionEvent: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let ts: String
    public let kind: String
    public let actorId: String?
    public let slotKey: String?
    public let payloadJson: String?

    enum CodingKeys: String, CodingKey {
        case id, ts, kind
        case actorId = "actor_id"
        case slotKey = "slot_key"
        case payloadJson = "payload_json"
    }

    /// Человеческое имя вида события. Неизвестный вид показываем как есть —
    /// новые виды не должны ломать экран.
    public var kindTitle: String {
        switch kind {
        case "contract_replaced": return "Контракт записан"
        case "assertion_results": return "Результаты проверки"
        case "assertion_failed": return "Ассерция не пройдена"
        case "assertion_blocked": return "Ассерция не проверяется вживую"
        case "gate_rework": return "Открыта доработка"
        case "mission_closed": return "Миссия закрыта"
        case "mission_skill_registered": return "Навык миссии записан"
        case "mission_skill_released": return "Навык миссии снят"
        default: return kind
        }
    }
}

/// Навык, написанный под миссию: у него есть срок жизни — при закрытии
/// карточки навык уходит в архив и перестаёт влиять на будущие задачи роли.
public struct MissionSkill: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let role: String
    public let name: String
    public let description: String
    public let sourceSlot: String?
    public let createdAt: String
    public let releasedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role, name, description
        case sourceSlot = "source_slot"
        case createdAt = "created_at"
        case releasedAt = "released_at"
    }
}

/// Покрытие контракта планом: какие ассерции не заявлены ни одной работой.
public struct AssertionCoverage: Decodable, Hashable, Sendable {
    public let ok: Bool
    public let total: Int
    public let violations: [AssertionViolation]
}

public struct AssertionViolation: Decodable, Hashable, Sendable {
    /// `uncovered` | `duplicate` | `unknown`.
    public let kind: String
    public let assertionId: String?
    public let slotKey: String?
    public let message: String

    enum CodingKeys: String, CodingKey {
        case kind, message
        case assertionId = "assertion_id"
        case slotKey = "slot_key"
    }
}
