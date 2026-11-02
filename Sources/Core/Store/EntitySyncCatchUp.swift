import Foundation

/// Догон сущностей вне карточек после разрыва связи.
///
/// Зачем. События сокета — сигнал «что-то изменилось», а не доставка: событие,
/// случившееся в разрыв, до телефона не приходит никогда. Карточки после
/// разрыва догоняются по своему журналу (`/api/tasks/changes`), а проекты,
/// метки, заметки и рутины — не догонялись вообще: правка рутины или заметки
/// на сервере оставалась на телефоне до перезагрузки экрана (разбор
/// 02.11.2026, заметка Архитектора «Техническое решение и риски»).
///
/// Как работает. Клиент спрашивает `GET /api/sync/changes` с курсором,
/// получает id изменившихся и исчезнувших сущностей по типам и решает, что
/// перечитать (`EntitySyncPolicy`). Тела сущностей не едут в дельте: локальной
/// копии этих сущностей на телефоне нет (У2 архитектурной заметки), поэтому
/// догон для них — перечитывание дешёвого списка целиком.
///
/// Курсор двигается ТОЛЬКО когда все шаги догона прошли: он означает «до
/// этого места я догнал», и сдвинуть его раньше применения — значит потерять
/// изменение навсегда.
@MainActor
final class EntitySyncCatchUp {
    /// Ключ курсора в `sync_state` локальной базы.
    ///
    /// Свой, а не общий с курсором карточек: у них разные журналы и разные
    /// окна хранения.
    static let cursorKey = "entities.cursor"

    /// Что нужно перечитать по дельте. Задаётся владельцем догона
    /// (обычно `TaskFlowApp`): у него есть сторы и экраны.
    ///
    /// Каждый обработчик возвращает `true`, если перечитывание прошло.
    /// `false` — шаг не применён, и курсор остаётся на месте: догон
    /// повторится целиком при следующем переподключении.
    struct Handlers {
        /// Перечитать список проектов.
        @MainActor var reloadProjects: () async -> Bool
        /// Перечитать список меток.
        @MainActor var reloadLabels: () async -> Bool
        /// Перечитать заметки (и разбудить экран заметок).
        @MainActor var reloadNotes: () async -> Bool
        /// Перечитать рутины (и разбудить экран рутин).
        @MainActor var reloadRoutines: () async -> Bool

        init(
            reloadProjects: @escaping @MainActor () async -> Bool = { true },
            reloadLabels: @escaping @MainActor () async -> Bool = { true },
            reloadNotes: @escaping @MainActor () async -> Bool = { true },
            reloadRoutines: @escaping @MainActor () async -> Bool = { true }
        ) {
            self.reloadProjects = reloadProjects
            self.reloadLabels = reloadLabels
            self.reloadNotes = reloadNotes
            self.reloadRoutines = reloadRoutines
        }
    }

    /// Что удалось применить — для отчёта и для проверок.
    struct Outcome: Sendable {
        /// Шаги, которые применились.
        var appliedSteps: [EntitySyncStep]
        /// Шаги, которые не прошли. Пустой список — курсор сдвинут.
        var failedSteps: [EntitySyncStep]
        /// Новый курсор (nil — курсор не сдвинулся).
        var cursor: String?
        /// `true` — журнал не покрыл момент, клиент перечитал всё целиком.
        var full: Bool
        /// `false` — сервер не отдал дельту (старый сервер без ручки или сеть
        /// не поднялась): клиент обязан перечитать справочники целиком.
        var serverReachable: Bool
    }

    private let apiClient: APIClient
    private let store: LocalStore

    init(apiClient: APIClient, store: LocalStore = .shared) {
        self.apiClient = apiClient
        self.store = store
    }

    /// Догнать изменения по курсору.
    ///
    /// Ошибка сети — не исключение наружу: догон повторится при следующем
    /// переподключении, а экран покажет текущие данные.
    func catchUp(handlers: Handlers) async -> Outcome {
        let cursor = store.syncState(Self.cursorKey)
        let delta: EntitySyncDelta
        do {
            delta = try await apiClient.entityChanges(since: cursor)
        } catch {
            return Outcome(
                appliedSteps: [],
                failedSteps: [],
                cursor: nil,
                full: false,
                serverReachable: false
            )
        }

        let plan = EntitySyncPolicy.plan(for: delta)
        var failed: [EntitySyncStep] = []
        var applied: [EntitySyncStep] = []

        if plan.reloadProjects {
            if await handlers.reloadProjects() { applied.append(.projects) }
            else { failed.append(.projects) }
        }
        if plan.reloadLabels {
            if await handlers.reloadLabels() { applied.append(.labels) }
            else { failed.append(.labels) }
        }
        if plan.reloadNotes {
            if await handlers.reloadNotes() { applied.append(.notes) }
            else { failed.append(.notes) }
        }
        if plan.reloadRoutines {
            if await handlers.reloadRoutines() { applied.append(.routines) }
            else { failed.append(.routines) }
        }

        // Курсор — только вместе с применёнными данными. Часть дельты не
        // применилась — курсор остаётся на месте, и догон повторится целиком.
        let canAdvance = EntitySyncPolicy.canAdvanceCursor(failedSteps: failed)
        if canAdvance {
            store.setSyncState(Self.cursorKey, delta.cursor)
        }
        return Outcome(
            appliedSteps: applied,
            failedSteps: failed,
            cursor: canAdvance ? delta.cursor : nil,
            full: delta.full,
            serverReachable: true
        )
    }
}
