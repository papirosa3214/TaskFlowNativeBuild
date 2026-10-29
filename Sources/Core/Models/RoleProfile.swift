import Foundation

// LOCK-176, этапы 2–3: профиль роли — то, чем «Команда» заменяет `ApiUser`.
//
// Источник — `GET /api/roles` (`server/src/routes/roles.ts`), единственный
// серверный фасад, который отдаёт роль целиком: модель и упорядоченные
// fallback, промпт, tools, скиллы, права, текущую задачу и проблемы. Спека
// фасада Pi (`docs/superpowers/specs/2026-09-18-pi-runtime-facade.md`)
// закрепила этот контракт за UI. `AgentProfile` из `/api/runtime/profiles`
// — подмножество без `current_task`; экрану нужен именно этот вид.
//
// Семантика миграции: исполнитель — роль (`AgentProfile`), Pi — runtime под
// ней и в обычном UI не показывается. Поэтому здесь нет ни provider, ни
// executionMode, ни API-токена.

public enum RoleRuntimeStatus: String, Codable, Sendable, Hashable {
    case ready, working, blocked, unavailable, unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = RoleRuntimeStatus(rawValue: raw) ?? .unknown
    }

    /// Запасной текст, если сервер не прислал `status_title`.
    public var title: String {
        switch self {
        case .ready: "Готова"
        case .working: "Работает"
        case .blocked: "Заблокирована"
        case .unavailable: "Недоступна"
        case .unknown: "—"
        }
    }
}

/// Чем роль занята прямо сейчас. На сервере выбирается по `dispatched_role` —
/// исполнитель у всех ролей один Pi, поэтому по `assignee_id` не вычислить.
public struct RoleCurrentTask: Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let state: String?
}

/// Установленный роли скилл (`role_skills`). На сервере поле `skill_name`.
public struct RoleSkill: Codable, Sendable, Hashable {
    public let name: String
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case name = "skill_name"
        case description
    }
}

/// Ступень лесенки попыток для модели роли (`attempt_policies`).
public struct RoleAttemptPolicy: Codable, Sendable, Hashable {
    public let reasonCode: String
    public let fromModel: String
    public let toModel: String?
    public let maxAttempts: Int
    public let cooldownSeconds: Int

    enum CodingKeys: String, CodingKey {
        case reasonCode = "reason_code"
        case fromModel = "from_model"
        case toModel = "to_model"
        case maxAttempts = "max_attempts"
        case cooldownSeconds = "cooldown_seconds"
    }
}

/// Инструмент роли вместе с описанием (`tools_detail` в `/api/roles`).
/// Описание присылает сервер из определения самого тула — раньше экран
/// показывал выдуманный вручную словарь, из-за чего у ролей, работающих
/// внутри сервера (Оркестратор), половина инструментов осталась без текста.
public struct RoleToolDetail: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let description: String?

    public var id: String { name }
}

/// Профиль роли как его отдаёт `/api/roles`.
public struct RoleProfile: Codable, Sendable, Hashable, Identifiable {
    public let role: String
    public let title: String
    public let accountID: String?
    public let status: RoleRuntimeStatus
    public let statusTitle: String
    /// Жив ли исполнитель (Pi). Общая причина на весь список, не свойство роли.
    public let runtimeReady: Bool
    /// Проблемы САМОЙ роли (промпт/профиль/учётка/модель). Пусто — всё цело.
    public let problems: [String]
    /// Системный промпт роли. `nil` — в лёгкой проекции списка (29.10.2026,
    /// «телефон — чисто окошко»): промпты всех ролей весили 258 КБ из 839 КБ
    /// ответа, а список их не рисует. Полный профиль — `GET /api/roles/:role`.
    public let prompt: String?
    /// Навыки роли. `nil` — в лёгкой проекции списка (см. `prompt`).
    public let skills: [RoleSkill]?
    public let tools: [String]
    /// Те же инструменты с серверными описаниями. `nil` у прежних сборок
    /// сервера — тогда экран рисует одни имена, ничего не выдумывая.
    /// Необязательное намеренно: поле появилось позже списка `tools`, и
    /// обязательное уронило бы разбор всего ответа роли на старом сервере.
    public let toolsDetail: [RoleToolDetail]?
    /// Операции внутри общего taskflow; без отдельного списка для внешних приложений.
    public let operationsDetail: [RoleToolDetail]?
    public let permissions: String?
    /// Primary-модель роли (`role-routing.yaml:models`).
    public let model: String?
    /// Legacy-alias оболочки; новым потребителям — `runtimeID`.
    public let defaultShell: String?
    public let runtimeID: String?
    /// Упорядоченные fallback-модели: порядок эскалации, сортировать нельзя.
    public let fallbacks: [String]
    public let attemptPolicy: [RoleAttemptPolicy]
    public let currentTask: RoleCurrentTask?
    public let lastActivity: String?
    /// «Чем занимается» — владелец задаёт его в экране «Команда» (LOCK-205).
    /// Для прежних ролей сервер может не прислать (миграция `057_roles_prompt`
    /// его не трогала) — `nil` означает «не задано», и в строке списка поле
    /// просто не показывается.
    public let summary: String?
    /// Включена ли роль. Сервер отдаёт его с момента, как появился
    /// `?all=1` (LOCK-205): владелец видит отключённые, чтобы было что
    /// включить обратно. `nil` — для прежних ответов без этого поля.
    public let enabled: Bool?
    /// Чем исполняется: `pi` — внутренняя роль, иначе внешний агент
    /// (`claude-code`, …) в своём окружении. `nil` у прежних серверов.
    public let runtime: String?

    public var id: String { role }

    /// Внешний агент (Claude Code и т. п.): своя модель и инструменты,
    /// поэтому строки модели Pi у него нет.
    public var isExternalAgent: Bool { (runtime ?? "pi") != "pi" }

    /// Удобный флаг для UI: включать в список, отдавать «живым» исполнителям.
    /// По умолчанию `true`, чтобы старые ответы без `enabled` не теряли роли.
    public var isEnabled: Bool { enabled ?? true }

    /// Серверная учётка может иметь любой ID: у помощника это u-secretary.
    public var canJoinChat: Bool {
        isEnabled && accountID.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true
    }


    /// Политика моделей в терминах `AgentProfile`.
    public var modelPolicy: AgentModelPolicy {
        AgentModelPolicy(primary: model ?? "", fallbacks: fallbacks)
    }

    public var hasProblems: Bool { !problems.isEmpty }

    /// Человеческая подпись статуса: серверная `status_title`, иначе своя.
    public var displayStatus: String {
        statusTitle.isEmpty ? status.title : statusTitle
    }

    enum CodingKeys: String, CodingKey {
        case role, title, status, problems, prompt, skills, tools, permissions, model, fallbacks
        case toolsDetail = "tools_detail"
        case operationsDetail = "operations_detail"
        case accountID = "account_id"
        case statusTitle = "status_title"
        case runtimeReady = "runtime_ready"
        case defaultShell = "default_shell"
        case runtimeID = "runtime_id"
        case attemptPolicy = "attempt_policy"
        case currentTask = "current_task"
        case lastActivity = "last_activity"
        case summary, enabled, runtime
    }
}
