import Foundation

/// Ход шага карточки дельтами (`tasks:live:start/patch/end`, владелец
/// 27.10.2026). Собирает ход по прогону и отдаёт экранам привычный снимок, а
/// старый полный `tasks:live` того же прогона глушит. Пропуск номера или
/// дельта без начала — прогон возвращается на старые снимки: сервер пока
/// шлёт оба формата, и экранам не нужен свой запрос снимка.
struct TaskLiveDeltaRouter {
    enum Action: Equatable {
        case show(RoleChatLiveTurnState, complete: Bool)
        case drop
        case pass
    }

    private var states: [String: RoleChatLiveTurnState] = [:]
    private var tracked: Set<String> = []

    mutating func route(_ delta: RoleChatLiveDelta) -> Action {
        let runID = delta.turnID
        if case .start(let state) = delta {
            states[runID] = state
            tracked.insert(runID)
            return .show(state, complete: false)
        }
        guard var state = states[runID] else { return fallBack(runID) }
        switch state.apply(delta) {
        case .applied:
            states[runID] = state
            return .show(state, complete: false)
        case .ended:
            states[runID] = nil
            return .show(state, complete: true)
        case .needsSnapshot:
            return fallBack(runID)
        case .ignored:
            return .drop
        }
    }

    /// Старый полный снимок прогона: глушим, пока прогон идёт дельтами.
    func routeSnapshot(runID: String) -> Action {
        tracked.contains(runID) ? .drop : .pass
    }

    /// После переподключения дельты могли потеряться — всё на старые снимки.
    mutating func reset() {
        states = [:]
        tracked = []
    }

    private mutating func fallBack(_ runID: String) -> Action {
        states[runID] = nil
        tracked.remove(runID)
        return .drop
    }
}
