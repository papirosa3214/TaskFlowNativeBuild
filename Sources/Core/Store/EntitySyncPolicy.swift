import Foundation

/// Правила догона сущностей вне карточек (проекты, метки, заметки, рутины).
///
/// Вынесены отдельным файлом без БД и без сети — только решения и разбор
/// ответа, — чтобы их можно было проверить на macOS без симулятора (в файле
/// нет ни GRDB, ни URLSession). Рядом лежит `TaskSyncCachePolicy.swift` — те
/// же правила для карточек.
///
/// Смысл — заметка «Техническое решение и риски» (карточка 2980844e):
/// источник правды — журнал на сервере и чтение по курсору. События сокета
/// ускоряют обновление, но пропуск события не ведёт к рассинхрону: после
/// разрыва клиент догоняет по курсору.
///
/// Локальной копии этих сущностей на телефоне нет (У2 архитектурной
/// заметки): они живут в памяти и берутся из сети. Поэтому догон для них —
/// не «применить тела», а «перечитать дешёвый список целиком», и курсор
/// двигается только после успешной перечитки.

/// Тип сущности вне карточек.
public enum EntitySyncKind: String, CaseIterable, Sendable {
    case projects
    case labels
    case notes
    case schedules
}

/// Изменения одного типа сущностей.
public struct EntitySyncBucket: Decodable, Sendable {
    public let changedIds: [String]
    public let removedIds: [String]

    enum CodingKeys: String, CodingKey {
        case changedIds = "changed_ids"
        case removedIds = "removed_ids"
    }
}

/// Ответ дельты синхронизации (`GET /api/sync/changes`).
///
/// Форма ответа — общая на все сущности:
///
/// ```
/// {
///   "server_time": "s:42",
///   "cursor": "s:42",
///   "full": false,
///   "entities": {
///     "projects":  { "changed_ids": [...], "removed_ids": [...] },
///     "labels":    { ... },
///     "notes":     { ... },
///     "schedules": { ... }
///   }
/// }
/// ```
///
/// Почему id, а не готовые строки (D6): точечных маршрутов «сущность по id»
/// у этих типов нет, а списки маленькие — клиент перечитывает список целиком.
public struct EntitySyncDelta: Decodable, Sendable {
    public let serverTime: String
    public let cursor: String
    /// `true` — журнал не покрывает запрошенный момент: клиент перечитывает
    /// всё целиком.
    public let full: Bool
    public let entities: [String: EntitySyncBucket]

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case cursor
        case full
        case entities
    }

    /// Корзина по имени типа; отсутствующий тип — пустая корзина (старый
    /// сервер без этого типа в дельте).
    public func bucket(_ name: String) -> EntitySyncBucket {
        entities[name] ?? EntitySyncBucket(changedIds: [], removedIds: [])
    }
}

/// Дельта в виде, пригодном для решения: без типов сети и без БД.
public struct EntitySyncPlanInput: Sendable {
    /// Журнал не покрывает запрошенный момент — клиент перечитывает всё.
    public var full: Bool
    /// Изменившиеся id по типам.
    public var changed: [EntitySyncKind: [String]]
    /// Исчезнувшие id по типам.
    public var removed: [EntitySyncKind: [String]]

    public init(
        full: Bool = false,
        changed: [EntitySyncKind: [String]] = [:],
        removed: [EntitySyncKind: [String]] = [:]
    ) {
        self.full = full
        self.changed = changed
        self.removed = removed
    }
}

/// Что именно перечитывать по дельте.
public struct EntitySyncPlan: Sendable, Equatable {
    public var reloadProjects: Bool = false
    public var reloadLabels: Bool = false
    public var reloadNotes: Bool = false
    public var reloadRoutines: Bool = false

    /// Плану нечего делать — догон не нужен.
    public var isEmpty: Bool {
        !reloadProjects && !reloadLabels && !reloadNotes && !reloadRoutines
    }
}

/// Шаг догона: что именно клиент перечитывает.
public enum EntitySyncStep: String, CaseIterable, Sendable {
    case projects
    case labels
    case notes
    case routines
}

public enum EntitySyncPolicy {
    /// Что перечитывать по дельте.
    ///
    /// `full: true` — читаем всё: журнал не покрывает нужный момент, и
    /// частичная перечитка оставила бы хвост старых данных.
    public static func plan(for input: EntitySyncPlanInput) -> EntitySyncPlan {
        var plan = EntitySyncPlan()
        if input.full {
            plan.reloadProjects = true
            plan.reloadLabels = true
            plan.reloadNotes = true
            plan.reloadRoutines = true
            return plan
        }
        func touched(_ kind: EntitySyncKind) -> Bool {
            !(input.changed[kind] ?? []).isEmpty
                || !(input.removed[kind] ?? []).isEmpty
        }
        plan.reloadProjects = touched(.projects)
        plan.reloadLabels = touched(.labels)
        plan.reloadNotes = touched(.notes)
        plan.reloadRoutines = touched(.schedules)
        return plan
    }

    /// План из ответа сервера.
    public static func plan(for delta: EntitySyncDelta) -> EntitySyncPlan {
        var changed: [EntitySyncKind: [String]] = [:]
        var removed: [EntitySyncKind: [String]] = [:]
        for kind in EntitySyncKind.allCases {
            let bucket = delta.bucket(kind.rawValue)
            changed[kind] = bucket.changedIds
            removed[kind] = bucket.removedIds
        }
        return plan(for: EntitySyncPlanInput(
            full: delta.full,
            changed: changed,
            removed: removed
        ))
    }

    /// Шаги, которые план требует выполнить.
    public static func steps(for plan: EntitySyncPlan) -> [EntitySyncStep] {
        var steps: [EntitySyncStep] = []
        if plan.reloadProjects { steps.append(.projects) }
        if plan.reloadLabels { steps.append(.labels) }
        if plan.reloadNotes { steps.append(.notes) }
        if plan.reloadRoutines { steps.append(.routines) }
        return steps
    }

    /// Курсор двигаем только когда ВСЕ шаги догона прошли.
    ///
    /// Курсор означает «до этого места я догнал». Сдвинутый раньше
    /// применения — значит потерянное изменение не придёт больше никогда.
    public static func canAdvanceCursor(failedSteps: [EntitySyncStep]) -> Bool {
        failedSteps.isEmpty
    }
}
