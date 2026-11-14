import Foundation

/// Список дел агента Pi в сессии владельца — готовые данные сервера
/// (`GET /api/sessions/:id/todos`, контракт New-Todoist
/// `docs/current/pi-todo-list-sessions.md`). Клиент ничего не разбирает: что
/// сервер прислал, то и рисуется полосой чек-листа чата (`ChatWorkPlanRows`),
/// поэтому вид и поведение кружков те же, что у плана роли.
struct SessionTodosResponse: Decodable {
    let todos: SessionTodos?
}

/// Один список дел сессии. `available: false` — агент ещё не звал инструмент
/// `todo`, это не ошибка; просроченные пункты (tombstones) сервер не отдаёт.
struct SessionTodos: Decodable, Equatable {
    let sessionId: String
    let available: Bool
    /// Из какой записи транскрипта снят список: по ней видно, что пришло новее.
    let entryId: String?
    let updatedAt: String?
    let nextId: Int?
    let tasks: [Task]
    let counts: Counts?

    enum CodingKeys: String, CodingKey {
        case sessionId, available, entryId, updatedAt, nextId, tasks, counts
    }

    /// Поля списка читаем терпимо: старый/урезанный ответ не должен пропасть
    /// целиком — без `tasks` и `available` список просто не показывается.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        entryId = try container.decodeIfPresent(String.self, forKey: .entryId)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        nextId = try container.decodeIfPresent(Int.self, forKey: .nextId)
        tasks = try container.decodeIfPresent([Task].self, forKey: .tasks) ?? []
        counts = try container.decodeIfPresent(Counts.self, forKey: .counts)
    }

    struct Task: Decodable, Equatable {
        let id: Int
        let subject: String
        /// Строкой, а не перечислением: незнакомый статус не должен ронять
        /// весь ответ — сервер вправе добавить своё состояние.
        let status: String
        let activeForm: String?
        let blockedBy: [Int]?
    }

    struct Counts: Decodable, Equatable {
        let pending: Int?
        let inProgress: Int?
        let completed: Int?

        enum CodingKeys: String, CodingKey {
            case pending
            case inProgress = "in_progress"
            case completed
        }
    }

    /// Идентификатор плана в пределах сессии: у сессий чек-лист один.
    static let planID = "pi-todos"
}

extension SessionTodos {
    /// План для полосы чек-листа. `nil` — показывать нечего: агент ещё не вёл
    /// список (`available: false`) или он пуст, и тогда полоса не появляется.
    func plan(sessionID: String) -> ChatWorkPlan? {
        guard available else { return nil }
        let items = tasks.map { task in
            SubtaskWorkPlan.Item(
                id: String(task.id),
                title: Self.title(task),
                state: Self.state(task)
            )
        }
        guard !items.isEmpty else { return nil }
        return ChatWorkPlan(
            chatID: sessionID,
            roleID: Self.planID,
            revision: nextId ?? items.count,
            items: items,
            updatedAt: updatedAt ?? "",
            status: .active,
            currentItemID: tasks.first { $0.status == Self.inProgress }.map { String($0.id) }
        )
    }

    /// Ложится ли пришедший список поверх того, что уже на экране. Поздний
    /// ответ на старый запрос не должен затереть новый, а список другой сессии
    /// — текущий (переключение на месте).
    static func isNewer(_ incoming: SessionTodos, than current: SessionTodos?) -> Bool {
        guard let current else { return true }
        guard incoming.sessionId == current.sessionId else { return false }
        if let incomingAt = incoming.updatedAt, let currentAt = current.updatedAt, incomingAt != currentAt {
            return incomingAt > currentAt
        }
        return incoming.entryId != current.entryId || incoming.tasks != current.tasks
    }

    static let inProgress = "in_progress"

    private static func state(_ task: Task) -> SubtaskWorkPlan.Item.State {
        switch task.status {
        case "completed": .done
        case Self.inProgress: .inProgress
        default: .pending
        }
    }

    /// У идущей задачи агент ведёт форму действия («проверяю маршрут») — её и
    /// показываем, как в самом Pi; остальные пункты — своим текстом.
    private static func title(_ task: Task) -> String {
        guard task.status == Self.inProgress,
              let activeForm = task.activeForm,
              !activeForm.isEmpty
        else { return task.subject }
        return activeForm
    }
}
