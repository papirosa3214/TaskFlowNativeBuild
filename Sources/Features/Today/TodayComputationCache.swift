import Foundation

/// Кэш снимка «Сегодня» — LOCK-OPT-PERF-20261022.
///
/// Снимок `TodayComputation` — самая тяжёлая величина на экране «Сегодня»:
/// около двадцати фильтров и шести сортировок по всему списку задач. Пока он
/// был вычисляемым свойством, он собирался заново на каждом проходе `body`
/// — и дважды за проход (тело экрана и тулбар), то есть на каждый кадр
/// прокрутки. Здесь лежит последний собранный снимок и ключ из всех входов:
/// пока входы те же, отдаётся тот же снимок, без пересборки.
///
/// Ключ сравнивается по значению, а не по идентичности: список задач приходит
/// из стора и меняется на месте (новое значение массива), поэтому сравнение
/// содержимого — единственный способ не отдать устаревший снимок.
///
/// Сами задачи в ключе НЕ лежат: `ApiTask` — это десятки полей, и сравнение
/// списка из сотен задач по значению на каждый проход `body` стоило дороже,
/// чем вся пересборка снимка. Вместо этого — ревизия списка из стора
/// (`TaskStore.tasksRevision`, растёт при любой правке задач) и идентификаторы
/// задач, попавших в снимок (список мог быть отфильтрован под раздел).
final class TodayComputationCache {
    static let shared = TodayComputationCache()

    /// Все входы, от которых зависит снимок. Пока хоть один отличается —
    /// снимок собирается заново.
    struct Key: Equatable {
        /// Ревизия списка задач из стора: любая правка задачи меняет её.
        let tasksRevision: Int
        /// Идентификаторы задач, попавших в снимок: отбор может измениться
        /// без смены ревизии стора (состав раздела, рутины).
        let allTaskIDs: [String]
        let currentUser: ApiUser?
        let agents: [ApiUser]
        let filters: TodayTaskFilters
        let showAgentTasks: Bool
        let visibleProjectIds: Set<String>
        let today: String
        let activeHourDate: String
        let isLoading: Bool
        let isError: Bool
    }

    private let lock = NSLock()
    private var storedKey: Key?
    private var storedValue: TodayComputation?

    /// Последний собранный снимок, если он построен по тем же входам.
    func snapshot(for key: Key) -> TodayComputation? {
        lock.lock()
        defer { lock.unlock() }
        guard let storedKey, storedKey == key else { return nil }
        return storedValue
    }

    /// Запомнить собранный снимок.
    func store(_ value: TodayComputation, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        storedKey = key
        storedValue = value
    }

    /// Сброс — только для тестов.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storedKey = nil
        storedValue = nil
    }
}
