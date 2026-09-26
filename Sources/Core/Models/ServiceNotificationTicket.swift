import Foundation

/// Контракт живого API `.110` — docs/2026-09-27-notifications-service-tickets-spec.md.
/// Base URL `http://192.168.1.110:5198`, без авторизации (LAN).
public struct ServiceTicketSummary: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let path: String
    public let title: String
    public let ts: String
    public let source: String
    public let level: String
    public let hasTriage: Bool
    public let snippet: String
    public let links: [String]

    enum CodingKeys: String, CodingKey {
        case id, path, title, ts, source, level
        case hasTriage = "has_triage"
        case snippet, links
    }
}

public struct ServiceTicketInboxResponse: Decodable, Sendable {
    public let date: String
    public let count: Int
    public let items: [ServiceTicketSummary]
}

/// Статус одного пункта из блока "## Итог по устранению" (Phase 4 backend —
/// на 27.09.2026 сервер этот блок ЕЩЁ НЕ дописывает; парсится по эталонному
/// шаблону `.110:~/Проекты/taskflow-уведомления/format/svodka-template.md`,
/// перепроверить на первом живом файле, когда Phase 4 будет сделана).
public enum ServiceTicketResolutionStatus: Sendable, Hashable {
    case fixed
    case unresolved(reason: String)
    /// options — 1-3 предложенных варианта из текста; "4) свой вариант" — не
    /// сюда, это всегда отдельное поле ввода в модалке (Task 6).
    case needsDecision(options: [String])
}

public struct ServiceTicketResolutionItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let problem: String
    public let status: ServiceTicketResolutionStatus
    /// Задача TaskFlow, к которой уйдёт комментарий/на которую ведёт "(исправлено)".
    /// nil, если ссылку не удалось найти рядом с пунктом — тогда UI не делает тап активным.
    public let taskId: String?

    public init(problem: String, status: ServiceTicketResolutionStatus, taskId: String?) {
        self.id = problem
        self.problem = problem
        self.status = status
        self.taskId = taskId
    }
}

public struct ServiceTicketDetail: Sendable, Hashable {
    public let title: String
    public let when: String
    public let from: String
    public let level: String
    public let isAlarm: Bool
    public let summaryText: String
    public let notWorkingText: String?
    public let diagnosticTaskId: String?
    public let resolutionItems: [ServiceTicketResolutionItem]

    public init(title: String, when: String, from: String, level: String, isAlarm: Bool,
                summaryText: String, notWorkingText: String?, diagnosticTaskId: String?,
                resolutionItems: [ServiceTicketResolutionItem]) {
        self.title = title
        self.when = when
        self.from = from
        self.level = level
        self.isAlarm = isAlarm
        self.summaryText = summaryText
        self.notWorkingText = notWorkingText
        self.diagnosticTaskId = diagnosticTaskId
        self.resolutionItems = resolutionItems
    }
}

extension ServiceTicketDetail: Identifiable {
    public var id: String { title + when }
}
